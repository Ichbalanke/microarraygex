package MicroarrayGEX::InputFile;

use strict;
use warnings;
use File::Basename;

our (@ISA, @EXPORT, @EXPORT_OK, $VERSION);

use Exporter;

$VERSION = 0.01;
@ISA = qw(Exporter);
@EXPORT = qw(loadInputFiles);

sub loadInputFiles($$$$){
    my ($sampleProbeFileName,$annotationFileName,$refAnnoColsDefault,$errorMessage) = @_;
    my $aListOfMessages = [];
    my $errorCounter = 0;
    my $errorLevel = "";
    my $countAnnotCols = 0;
	## sample probe profile file is required
	my $refSampleProbeData = readInputFile($sampleProbeFileName,$refAnnoColsDefault);
	## annotation file is required from April2011 but backwards
	## compatibility will be maintained (also for re-runs)
	my $refAnnotationData;
	
    %{$errorMessage} = (error_number => undef, error_message => "");

    ## check if annotation file is provided
    if($annotationFileName eq ""){
    	## if not, validate sample file only
    	validateInputFile($refSampleProbeData,$refAnnoColsDefault,$aListOfMessages,"ERROR");
    }else{
    	## read then validate annotation file
		$refAnnotationData = readInputFile($annotationFileName,$refAnnoColsDefault);
		validateInputFile($refAnnotationData,$refAnnoColsDefault,$aListOfMessages,"ERROR");
		## validate the Sanple Probe data file with Warnings 
		## in case it contain annotation columns
		validateInputFile($refSampleProbeData,$refAnnoColsDefault,$aListOfMessages,"WARNING");
    }
    
    $errorCounter = grep(/Error/, @{$aListOfMessages});
    $countAnnotCols = grep(/Info: default annotation columns present/, @{$aListOfMessages});
    
    if($errorCounter){
    	unshift(@{$aListOfMessages},"\n\n$errorCounter error(s) found! Please verify your input files.\n\n");
    	$errorMessage->{error_number} = 1;
    }else{
    	push(@{$aListOfMessages},"\nNo errors found.\n");
    	$errorMessage->{error_number} = 0;
    }
    
    $errorMessage->{error_message} = join("",@{$aListOfMessages});
    
    if ($errorCounter>0){
    	## can't continue if any errors
    	return;
    }elsif($annotationFileName eq ""){
    	## no annotation file to merge
    	return;
    }elsif($countAnnotCols > 0){
    	## annotation columns present in Sample Probes file. Don't merge
    	return;
    }else{
    	## merge files
    	## if any IO error occurs in mergeInputfiles the whole program dies
    	print "\n\n       Merging: $sampleProbeFileName and $annotationFileName :\n";
    	mergeInputFiles($sampleProbeFileName,$annotationFileName,$refSampleProbeData,$refAnnotationData);
    }
}

sub readInputFile($$){
	my ($fileName,$refAnnoColsDefault) = @_;
	my $header = "";
	my %hInputData;
	my @aInputHdrNames;
	my $colOrder = 0;
	my $rowNum = 0;
	my $firstAnnoCol = 0;
	my $colNamesRow = 0;
	## open the file and read it 
	open FH, "$fileName" or die "Couldn't open file $fileName";
	while(<FH>){
		chomp($_);
		$rowNum++;
		if($_ =~ /^TargetID/){
			## read only first probe dample line and extract column headers
			@aInputHdrNames = split(/\t+/,$_);
			foreach my $colName (@aInputHdrNames){
				## column order is 0-based
				$hInputData{$colName}=$colOrder;
				# if current column is an annotation column and no other has
				# been found, save that number as the first annotation column
				if(($refAnnoColsDefault->{$colName})&&(!$firstAnnoCol)){
					$firstAnnoCol = $colOrder;
				}
				$colOrder++;
			}
			$colNamesRow = $rowNum;
			## stop reading the file
			last;
		}
	}
	## add headers array as an extra key to save the order
	$hInputData{inputhdrnames} = \@aInputHdrNames;
	## save the number of the first annotation column
	$hInputData{firstannocol} = $firstAnnoCol;
	## save the row number where the column names are located
	$hInputData{colnamesrow} = $colNamesRow;
	## return the data structure
	return \%hInputData;
}

sub validateInputFile($$$$){
	my ($refInputData,$refListDefAnnoCols,$refListOfMessages,$errorLevel) = @_;
	## extract array of headers
	my @aInputHdrNames = @{$refInputData->{inputhdrnames}};
	my %hDefaultAnnotCols = %{$refListDefAnnoCols};
	my $countAnnotCols = 0;
	## first two columns must be: TargetID,ProbeID
	(@aInputHdrNames > 2) || die "Not worth checking. Too few columns\n"; 
	if(lc($aInputHdrNames[0]) ne "targetid"){
		push @{$refListOfMessages}, "Error: First column is not 'TargetID'\n";
	}
    if(lc($aInputHdrNames[1]) ne "probeid"){
        push @{$refListOfMessages}, "Error: Second column is not 'ProbeID'\n";
    }
	## look for annotation columns
	foreach my $annotationCol(keys %hDefaultAnnotCols){
		if($errorLevel eq "ERROR"){
			if(!exists $refInputData->{$annotationCol}){
				push @{$refListOfMessages}, "Error: annotation column $annotationCol is not present\n";
			}
		}elsif($errorLevel eq "WARNING"){ 
			if(exists $refInputData->{$annotationCol}){
				push @{$refListOfMessages}, "Warning: annotation column $annotationCol present in Sample Probes file\n";
				$countAnnotCols++;
			}			
		}
	}
	if($countAnnotCols>0){
		push @{$refListOfMessages}, "\nInfo: default annotation columns present in Sample Probes file, annotation file will be ignored\n";
	}elsif($countAnnotCols == 0 && $errorLevel eq "ERROR"){
		push @{$refListOfMessages}, "\nInfo: some or all default annotation columns are not present in Sample Probes file, an Annotation file may be required.\n";
	}
}

sub mergeInputFiles($$$$){
	my ($sampleProbeFileName,$annotationFileName,$refSampleProbeData,$refAnnotationData) = @_;
	my $commandLine = "";
	my $successMsg = "";
	my $errorMsg = "";
	my $sampFileRowCut = $refSampleProbeData->{colnamesrow}-1;
	my $annoFileRowCut = $refAnnotationData->{colnamesrow} - 1;
	## copy header from annotation file and paste it in the final file
	$commandLine = "sed -n '1,".$annoFileRowCut."p;".$annoFileRowCut."q' ".$annotationFileName." > final.txt ; dos2unix final.txt";
	$errorMsg = "An error occured while trying to cut the header from sample probes file.";
	$successMsg = "\n       9, $commandLine";
	execute_system($commandLine,$errorMsg,$successMsg);
	## remove header from sample probes file (save result as a temp file)
	$commandLine = "sed '1,".$sampFileRowCut."d' ".$sampleProbeFileName." > sampleheaderless_temp.txt";
	$errorMsg = "An error occured while trying to remove the header from sample probes file.";
	$successMsg = "\n       8, $commandLine";
	execute_system($commandLine,$errorMsg,$successMsg);
	## remove header from annotation file (save result as a temp file)
	$commandLine = "sed '1,".$annoFileRowCut."d' ".$annotationFileName." > annoheaderless_temp.txt";
	$errorMsg = "An error occured while trying to remove the header from annotation file.";
	$successMsg = "\n       7, $commandLine";
	execute_system($commandLine,$errorMsg,$successMsg);
	## remove trailing tabs from sample probes file (save result as a temp file)
	$commandLine = "dos2unix sampleheaderless_temp.txt ; sed 's/\\t\$//' sampleheaderless_temp.txt > sampleheaderless2_temp.txt";
	$errorMsg = "An error occured while trying to remove trailing tabs from sample probes file.";
	$successMsg = "\n       6, $commandLine";
	execute_system($commandLine,$errorMsg,$successMsg);
	## remove trailing tabs from annotation file (save result as a temp file)
	$commandLine = "dos2unix annoheaderless_temp.txt ; sed 's/\\t\$//' annoheaderless_temp.txt > annoheaderless2_temp.txt";
	$errorMsg = "An error occured while trying to remove trailing tabs from annotation file.";
	$successMsg = "\n       5, $commandLine";
	execute_system($commandLine,$errorMsg,$successMsg);
	## cut annotation columns from annotation file
	my $numColumns = scalar @{$refAnnotationData->{inputhdrnames}}+1;
	$commandLine = "cut -f 3-".$numColumns." annoheaderless2_temp.txt > annotationcols_temp.txt";
	$errorMsg = "An error occured while trying to cut annotation columns from annotation file.";
	$successMsg = "\n       4, $commandLine";
	execute_system($commandLine,$errorMsg,$successMsg);	
	## paste probes and annotation files together
	$commandLine = "paste sampleheaderless2_temp.txt annotationcols_temp.txt > probesandannotation_temp.txt";
	$errorMsg = "An error occured while trying to paste probes and annotation files.";
	$successMsg = "\n       3, $commandLine";
	execute_system($commandLine,$errorMsg,$successMsg);	
	## append probes and annotation columns to final.txt file
	$commandLine = "cat probesandannotation_temp.txt >> final.txt";
	$errorMsg = "An error occured while trying to append data to final file.";
	$successMsg = "\n       2, $commandLine";
	execute_system($commandLine,$errorMsg,$successMsg);
	## rename final.txt file to proper input file name
	$commandLine = "mv final.txt $sampleProbeFileName";
	$errorMsg = "An error occured while trying to rename final file.";
	$successMsg = "\n       1, $commandLine";
	execute_system($commandLine,$errorMsg,$successMsg);
	## delete temporal files
	$commandLine = "rm *temp.txt";
	$errorMsg = "An error occured while trying to delete temporal files.";
	$successMsg = "\n       0 $commandLine ... Done!";
	execute_system($commandLine,$errorMsg,$successMsg);	
}

sub execute_system($$$){
	my ($command,$errorMsg,$successMsg) = @_;
	system($command);
	if($? == -1){
		print "$errorMsg: $!\n";
	}else{
		print "$successMsg";
	}	
}

1;