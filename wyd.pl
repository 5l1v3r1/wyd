#!/usr/bin/perl
#
# wyd.pl by Max Moser and Martin J. Muench
#
#  [ Licence ]
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#  See 'docs/gpl.txt' for more information.

use strict;
use FileHandle;
use File::Find;
use File::Basename;
use Getopt::Long;

my $version  = "0.2";  # version

my @listoffiles;       # The list of files to process
my $fileprog = undef;  # scalar that is filled with 'file' program

# Module hash containing module name and supported file extensions
# Multiple extensions are seperated using ';'
my %wlgmods = (
	       'wlgmod::strings', '',           # only used with command-line switch
	       'wlgmod::plain'  , '.txt',       # used for all MIME text/plain as well
	       'wlgmod::html'   , '.html;.htm;.php;.php3;.php4',
	       'wlgmod::doc'    , '.doc',
	       'wlgmod::pdf'    , '.pdf',
	       'wlgmod::mp3'    , '.mp3',
	       'wlgmod::ppt'    , '.ppt',
	       'wlgmod::jpeg'   , '.jpeg;.jpg;.JPG;.JPEG',
	       'wlgmod::odt'    , '.odt;.ods;.odp'
	       );

# Hash that will be filled dynamically with filehandles (if -t is used)
my %file_handle = ();

#### Begin main ####

# Print Header
print STDERR "\n*\n* $0 $version by Max Moser and Martin J. Muench\n*\n\n";

# Check command line options
my %opts;
my $strings_check  = undef;
my $output_file    = undef;
my $separate_types = undef;
my $no_filenames   = undef;
my $debug          = undef;      # set to "1" for debugprints -v will do this on command line
my $prefixclean    = undef;
my $postfixclean   = undef;
my $no_missingask  = undef;

# Parse command line
&usage if !GetOptions ('s=i' => \$strings_check, 
		       'o=s' => \$output_file,
		       'v+'  => \$debug,
		       'e+'  => \$postfixclean,
		       'b+'  => \$prefixclean , 
		       't+'  => \$separate_types, 
		       'f+'  => \$no_filenames,
		       'n+'  => \$no_missingask);


# -t used without -o
&usage if($separate_types && !$output_file);

# No file(s)/dir(s) given
&usage if($#ARGV < 0);

# Add given file(s)/directories to array
for(my $i = 0 ; $i <= $#ARGV ; $i++) {
    # File/Dir does not exist
    if ( ! -e $ARGV[$i]) {
	die "\nError, $ARGV[0] does not exist.\n\n";	
    }
    # Directory given
    elsif ( -d $ARGV[$i])
    {
	# Its a directory so we first generate a list of all files with names
	print "\n Its a directory \n" if $debug;

	$ARGV[$i] = qw(.) unless $ARGV[$i];

	find sub { 
	    push @listoffiles, $File::Find::name if -f 		
	}, $ARGV[$i];
	
    }
    # Single File
    elsif (-f $ARGV[$i])  {
	push @listoffiles, $ARGV[$i];
    }
    else {
	die "\n* Error: $ARGV[$i] is not a directory and not a regular file.\n* Sorry, for now this is unsupported.\n\n";
    }
    
}

print "\n\nThats the list to process: @listoffiles\n\n" if $debug;


# Initialize modules
if (!&check_n_init) { 
    die "\n* Processing aborted\n\n"; 
}

# Open outputfile if requested
if($output_file && !$separate_types) {
    open(OUTPUT, ">$output_file") || die "\n* Cannot open output file: $!\n";
}
# Create output files for all types if requested
elsif($output_file && $separate_types) {
    foreach (keys %wlgmods) {
	$_ =~ s/wlgmod:://;
	my $fh =  new FileHandle "$output_file.$_", "w";
	if(!$fh) {
	    die "\n* Cannot create $output_file.$_: $!\n";
	}
        $file_handle{$_} = $fh;
    }
}

# We progress now with processing the files and produce the output
foreach my $singlefile (@listoffiles)
{
    # Get words using modules
    my ($type, @words) = get_words($singlefile);

    # Print to given output (STDOUT || file)

    my $numentries = @words;
    if($numentries > 0) {
	print "---- Words in $singlefile -----\n\n"  if $debug;

	foreach my $wort (unique (\@words)) 
	{
	    # Write to single file
	    if($output_file && !$separate_types) {
		print OUTPUT "$wort\n";
	    }
	    # Write to type-specific output files
	    elsif($output_file && $separate_types) {
		foreach(keys %file_handle) {
		    if($_ eq $type) {
			my $fh = $file_handle{$_};		
			print $fh "$wort\n";
		    }
		}
	    }
	    else {
		print "$wort\n";
	    }
	} 
	
	print "\n----- $singlefile -----\n" if $debug;
    }
}

# single out
if($output_file && !$separate_types) {
    close(OUTPUT);
}
# single file for each type
elsif($output_file && $separate_types) {
    foreach(keys %file_handle) {
	my $fh = $file_handle{$_};
	close($fh);
	# remove empty files
	my $file = "$output_file.$_";
	unlink $file if -z $file;
    }
}


print STDERR "\n** Done\n\n";

exit(0);

#### End of main ####

# Load needed plugin and extract words
sub get_words {
    my ($file)     = @_;
    my $found      = 0;
    my @words      = undef;
    my $type       = undef;
    my $file_name  = undef;
    my $file_dir   = undef;
    my $file_ext   = undef;

    ($file_name, $file_dir, $file_ext) = fileparse($file,'\..*');

    # Look for matching module and get words
    foreach(keys %wlgmods) {
	my @ext = split(";", $wlgmods{$_});
	foreach my $extension (@ext) {
	    if($file_ext eq $extension) {
		$type = $_;
		@words = $_->get_words($file);
		$found=1;
		last;
	    }
	}
    }

    # If no module is found, do further checks
    if(!$found) {
	# Check MIME type, if ascii try plain-text module
	open(FILE, "$fileprog -bi \"$file\"|") || die "Cannot execute file: $!\n";
	my $type = <FILE>;
	close(FILE);
	if($type =~ m/^text\/plain/) {
	    print "'file' MIME check returned text/plain\n" if $debug;
	    $type = "wlgmod::plain";
	    @words = wlgmod::plain->get_words($file);
	}
	# Use strings module
	elsif($strings_check) {
	    # Check if strings module available
	    foreach(keys %wlgmods) {
		if($_ eq "wlgmod::strings") {
		    $type = "wlgmod::strings";
		    @words = wlgmod::strings->get_words($file,$strings_check);
		}
	    }
	}
	# Give up and ignore file
	else {
	    print STDERR "Ignoring file '$file'\n";
	    return (undef, undef);
	}
    }

    # Add filename itself to wordlist (without path/extension)
    if(!$no_filenames) {
	push @words, $file_name;
    }

    # Remove brackets quotes etc.
    my @Cleanedwords;
    foreach (@words) {
	s/^\W*(.*)/$1/	unless $prefixclean;
	s/^(.*)\W+$/$1/ unless $postfixclean;		
	push @Cleanedwords,$_;
    }

    # Cleanup type for high-level func
    $type =~ s/wlgmod:://;

    return ($type, @Cleanedwords);

} # End sub getwords

# Check modules for availability and init or remove them
sub check_n_init {
    my $retvals = undef;

    # Check for 'file'
    open(FILE, "which file|");
    chomp($fileprog = <FILE>);
    close(FILE);
    if($?) {
	$fileprog = undef;
	$retvals .= "file: Cannot locate 'file', skipping MIME type check on unknown files";
    }

    # Initialize possible modules
    foreach(keys %wlgmods) {
	eval("use $_;");
	my $ret = $_->init();
	# If module failed, add errortext and remove from hash
	if($ret) {
	    $retvals .= "$_: $ret\n";
	    delete $wlgmods{$_};
	    $ret = "";
	}
    }

    # If one or more modules failed, let user decide what to do
    if($retvals) {
	print STDERR "\n* Error initializing some modules:\n\n$retvals\n";
	# prompt user what to do if not disabled
	if(!$no_missingask) {
	    print STDERR "* Press enter to disable them and continue or STRG+C to abort\n";
	    <STDIN>;
        }
    }

    return 1;
}


# Make resulting list entries unique
sub unique {
    my $reflist = shift;
    my @uniq    = undef;
    my %seen    = ();
    @uniq = grep { ! $seen{$_} ++ } @$reflist;
    return @uniq;
}

# print usage and exit
sub usage {
print qq~Usage: $0 [OPTIONS] <file(s)|directory>

       Options: 

       -o <file>     = Write wordlist to <file>
       -t            = Separate wordlist files by type, e.g. '<file>.doc'
       -s <min-len>  = Use 'strings' for unsupported files
       -b            = Disable removal of non-alpha chars at beginning of word
       -e            = Disable removal of non-alpha chars at end of word
       -f            = Disable inclusion of filenames in wordlist        
       -v            = Show debug / verbose output
       -n            = Continue even if programs / modules are missing

~;
exit(1);
}

#### EOF #####
