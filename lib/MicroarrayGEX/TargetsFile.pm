package MicroarrayGEX::TargetsFile;

use strict;
use warnings;
use File::Basename;
use YAML::XS qw(LoadFile 
                Load);
use File::Slurp qw(slurp);

our (@ISA, @EXPORT, @EXPORT_OK, $VERSION);

use Exporter;

$VERSION = 0.01;
@ISA = qw(Exporter);
@EXPORT = qw(loadTargets formatTargetsOutput);

sub readTargets($){
	my $fileName = shift;
	my $header = "";
	my %hHdrNames;
	my @aHdrNames;
	## open the file and read it 
	open FH, "<:crlf", "$fileName" or die "Couldn't open file $fileName";
	my $firstLine = 1;
	while(<FH>){
		chomp($_);
		## read first line and extract column headers
		if($firstLine){
			@aHdrNames = split(/\t+/,$_);
			foreach my $column (@aHdrNames){
				$hHdrNames{$column}=[];
			}
			## add headers array as an extra key to save the order
			$hHdrNames{header} = \@aHdrNames;
			$firstLine = 0;
			next;
		}
		## read the remaining of the file
		## and save it into a data structure
		my @row = split (/\t+/,$_);
		my $numOfCols = keys(%hHdrNames);
		my $colNum = 0;
        foreach my $column (@aHdrNames){
        	push @{$hHdrNames{$column}}, $row[$colNum];
        	$colNum++;
        }
	}
	## return the data structure
	return \%hHdrNames;
}

sub formatTargetsOutput($$$){
	## get parameters
	my ($refTargetsData, $fileName, $deleteFileNameCol) = @_;
	
	## all these lines to get the longest value for each column
	## including the name of the column itself
	my @columns = @{$refTargetsData->{header}};
	#my %columnLengths = map{$_ => length($_)} @columns;
	my %columnLengths = map{$_ => length($_)} @columns;
	my (@colValues, $longest, $colName, @valueLengths);
	foreach my $column (@columns){
	    @colValues = @{$refTargetsData->{$column}};
	    @valueLengths = map{length($_)} @colValues;
	    @valueLengths = sort {$b <=> $a} @valueLengths;
	    $longest = $valueLengths[0];
	    $columnLengths{$column} = $longest if ($longest > $columnLengths{$column});
	}
	
	## instead of coding to get a super cols-to-lines subroutine we "slurp" the targets file
	## as lines to insert them into the wiki's main text after being formatted
	my $targetsText = "";
	my (@cols, @formatCols);
	my $pad_len = 0;
	my $colNum = 0;
	my $col = "";
	my @targetsLines = slurp($fileName);
	foreach my $line (@targetsLines){
	    chomp($line);
	    @cols = split(/\t/,$line);
	    $colNum = 0;
	    ## format elements of the array
	    foreach $col(@cols){
	        $pad_len = $columnLengths{$columns[$colNum++]};
	        $col = sprintf("%-*s", $pad_len, $col);
	        ## ignore the input file name colum if explicitly required
	        if(($colNum==3)&&($deleteFileNameCol)){
	        	$col = "";
	        }
	    }
	    ## join them together
	    $targetsText = $targetsText."\n ".join("     ",@cols);
	}
	$targetsText = " ".$targetsText;
    return ($targetsText);
}

sub validateTargets($$$){
	my ($targets, $inputFileName, $refListOfMessages) = @_;
	## $inputFileName
	my ($inputName,$inputDirectories, $inputSuffix) = fileparse($inputFileName, qr/\.[^.]*/);
	## extract array of headers
	my @aHdrNames = @{$targets->{header}};
	## first four columns must be: arrayNumber, name, fileName and sampleID
	(@aHdrNames >= 3) || die "Not worth checking. Too few columns"; 
	if($aHdrNames[0] eq "arrayNumber"){
		push @{$refListOfMessages}, "       First column is 'arrayNumber': OK\n";
	}else{
		push @{$refListOfMessages}, "Error: First column is not 'arrayNumber'\n";
	}
    if($aHdrNames[1] eq "name"){
        push @{$refListOfMessages}, "       Second column is 'name': OK\n";
    }else{
        push @{$refListOfMessages}, "Error: Second column is not 'name'\n";
    }
    if($aHdrNames[2] eq "fileName"){
        push @{$refListOfMessages}, "       Third column is 'fileName': OK\n";
    }else{
        push @{$refListOfMessages}, "Error: Third column is not 'fileName'\n";
    }
    if (!exists $targets->{fileName}){
        push @{$refListOfMessages}, "Error: Column 'fileName' doesn't exist!\n";
    }
    ## can't continue if any of the errors above happen
    return if grep(/Error/, @{$refListOfMessages});
    ## otherwise review all columns in more deepth
    ## these variables will help the next bunch of validations
    my %seen = ();
    my (@uniq, $item);
    my $espChrFound = 0;
    my $startsWithNum = 0;
    foreach my $column(@aHdrNames){
    	if($column eq "arrayNumber"){
		    ## values in column arrayNumber must be unique
		    ## first get unique values from column
		    foreach $item (@{$targets->{arrayNumber}}) {
		        push(@uniq, $item) unless $seen{$item}++;
		    }
		    ## then confirm uniqueness by comparing both arrays
		    if(scalar @uniq != scalar @{$targets->{arrayNumber}}){
		        push @{$refListOfMessages}, "Error: Non-unique values in 'arrayNumber'!\n";
		    }    		
    	}elsif($column eq "name"){
            #my $inputFileName = ${$targets->{fileName}}[0];
            my $inputLine = "";
            my $inputLineNum = 0;
            my $readHeaderLine = 0;
            my %inputFileArrayNames;
            ## values must exist in the input file
            ## open input file and look for them in column headers
            open FHIN, $inputFileName or die "Couldn't find input file $inputFileName";
            while(<FHIN>){
                $inputLine = $_;
                chomp($inputLine);
                $inputLineNum++;
                if((($inputLine =~ /^\[.*\]/)&&($inputLineNum>1))){
                    $readHeaderLine=+1;
                    next;
                }
                ## read from the column headers
                if((($readHeaderLine)&&($inputLine =~ /^TargetID/))||($inputLine =~ /^TargetID/)){
                    ## get unique array name values
                    while($inputLine =~ /\d{10,12}_[A-L]+/g){
                        $inputFileArrayNames{$&} = 1 if(!exists $inputFileArrayNames{$&});
                    }
                    last;
                }
            }
            close(FHIN);
		    %seen = ();
		    @uniq = ();
		    $item = "";
		    ## values must exist in the input file
		    ## and at the same time must be unique 
		    foreach $item (@{$targets->{name}}) {
		        push(@uniq, $item) unless $seen{$item}++;
		        if(!exists $inputFileArrayNames{$item}){
		            push(@{$refListOfMessages},"Error: In column '$column' array '$item' doesn't exist in input file!\n");
		        }
		    }
		    ## confirm uniqueness by comparing both arrays
		    if(scalar @uniq != scalar @{$targets->{arrayNumber}}){
		        push @{$refListOfMessages}, "Error: Non-unique values in column '$column'!\n";
		    }
    	}elsif($column eq "fileName"){
		    ## values in column fileName must be all the same
		    %seen = ();
		    @uniq = ();
		    $item = "";
		    foreach $item (@{$targets->{fileName}}) {
		        push(@uniq, $item) unless $seen{$item}++;
		    }
		    if(scalar @uniq > 1){
		        push @{$refListOfMessages}, "Error: Column 'fileName' has more than one value!\n";
		    }else{
		    	if($inputName.$inputSuffix ne $uniq[0]){
		    		push @{$refListOfMessages}, "Error: Name in Column 'fileName' ($uniq[0]) does not match second ARGV ($inputName)!\n";
		    	}
		    }
    	}elsif(lc($column) eq "description"){
    		## column 'description' (if present) can contain almos any value
    		next;
    	}else{
	  		## any value in the column can include any of these characters: -, +, *, /, \, (, ) or whitespace
	   		$espChrFound = 0;
	   		$startsWithNum = 0;
	   		foreach $item (@{$targets->{$column}}) {
	   			$espChrFound+=1 if($item =~ /-|\+|\*|\/|\\|\(|\(| /);
	   			$startsWithNum+=1 if($item =~ /^\d/);
	    	}
	    	if($espChrFound){
	    		push @{$refListOfMessages}, "Error: Values in column '$column' can't include -, +, *, /, \, (, ) or whitespace!\n";
	    	}
	    	if($startsWithNum){
	    		push @{$refListOfMessages}, "Error: Values in factor column '$column' can't start with a number!\n";
	    	}
	    	if(($startsWithNum+$startsWithNum)==0){
	    		push @{$refListOfMessages}, "       Column '$column' seems OK\n";
	    	}
	    }
    }
}

## ------------------------- start  main ------------------------- ##
sub loadTargets($$$){
    my ($targetsFileName, $inputFileName, $errorMessage) = @_;
    my $aListOfMessages = [];
    my $errorCounter = 0;
    my $refTargetsData = readTargets($targetsFileName);

    %{$errorMessage} = (error_number => undef, error_message => "");

    ## validate contents
    validateTargets($refTargetsData, $inputFileName, $aListOfMessages);

    ## read list of messages and display results
    #foreach my $msg (@{$aListOfMessages}){
    #   $errorCounter++ if ($msg =~ /^Error/);
    #}
    
    $errorCounter = grep(/Error/, @{$aListOfMessages});

    if($errorCounter){
    	unshift(@{$aListOfMessages},"\n\n$errorCounter error(s) found! Please verify your targets file.\n\n");
    	$errorMessage->{error_number} = 1;
    }else{
    	push(@{$aListOfMessages},"\nNo errors found.\n");
    	$errorMessage->{error_number} = 0;
    }
    
    $errorMessage->{error_message} = join("",@{$aListOfMessages});
    
    return($refTargetsData);
}
## -------------------------- end  main -------------------------- ##

1;

__END__

=head1 NAME

TargetsFile.pm

=head1 SYNOPSYS

A small simple module that contains subroutines to load and validate the
contents of a targets file.

=head1 DESCRIPTION


Targets files are an essential component of Microarray data analysis. This
simple module loads and validates its contents. Starts by loading the file
into data structure which is in turn validated to secure a minimum of
correctness of the file.

The loading subroutine implements both sub tasks, reading and validating the
targets file returning the data structure in case of success or error in case
of failure; but the component subroutines might be called by them selves too. 

=head1 SUBROUTINES

My superSmart subroutines:

=head2 - readTargets($fileName)

=over 2

Read the targets file and returns a data structure.

=over 12

=item Type:

Function

=item Arguments:

$fileName: /path/to/targets_file.txt specified in the Experiment's yaml file.

=item Return:

A data structure representing the contents of the targets file.

=back

=back

=head2 - validateTargets($refTargetsData, $inputFileName, $refListOfMessages)

=over 2

Validates the data structure created by readTargets to verify whether the 
targets file is correct. 

=over 12

=item Type:

Procedure

=item Arguments:

$refTargetsData: reference to the targets file's data structure.

$inputFileName: path to input file.

$refListOfMessages: "by reference" variable addressing to an empty array to
hold the error messages generated from the validation of the targets file's
data structure.

=back

=back

=head2 - formatTargetsOutput($refTargetsData, $fileName, $deleteColumn)

=over 2

Formats the contents of the targets file leaving it ready for posting in the
wiki page file. It looks for the largest string length within each colum and
uses that value to align the contents of the columns to the right.

=over 12

=item Type:

Function

=item Arguments:

$targetsHash: reference to the targets file's data structure.

$fileName: /path/to/targets_file.txt specified in the Experiment's yaml file.

$deleteFileNameCol: Indicates whether the column containing the name
of the input file (fileName) must be included or not in the output. 

=item Return:

A scalar containing the formatted targets file (basically a big string).

=back

=back

=head2 - loadTargets($targetsFile, $errorMessage)

=over 2

"Wrapper" for the first two subroutines. This is the subroutine that should be
called when using the module. 

=over 12

=item Type:

Function

=item Arguments:

$fileName: /path/to/targets_file.txt specified in the Experiment's yaml file.

$errorMessage: "by reference" variable addressing to an empty hash with two
keys, error_number and error_message. First one is 0 if the targets file is
100% correct, 1 otherwise. error_message may contain both kinds of messages:
error and no error.

=item Return:

A data structure representing the contents of the targets file. 

=back

=back

=head1 HISTORY

=item rb11100927: add formatTargetsOutput function and updated documentation.

=item rb11101005: add parameter $inputFileName to function validateTargets.

=head1 AUTHOR

 -------------------------------------------------------------------------------
 Created at: Wellcome Trust Sanger Institute
 On        : 09/09/2010
 By        : R.E. Bautista-Garcia (rb11)
 Update    : 05/10/2010 
 -------------------------------------------------------------------------------