package MicroarrayGEX::ExperimentFile;

use strict;
use warnings;

our (@ISA, @EXPORT, @EXPORT_OK, $VERSION);
 
use Exporter;

$VERSION = 0.01;
@ISA = qw(Exporter);
@EXPORT = qw(validateExperiment);
@EXPORT_OK = qw(generateCombinations validateExperiment);

sub generateCombinations($$){
    ## get list of factors and targets file
    my ($factors,$targets) = @_;
    ## local variables
    my %factorCombinations = ();
    ## count the number of factors before we start extracting them 
    my $numOfFactors = @{$factors};
    ## extract first factor to combine
    my $iniFactor = shift(@{$factors});
    ## extract first factor's values from targets file
    my @iniFactorValues = @{$targets->{$iniFactor}};
    my $nxtFactor;
    my @nxtFactorValues;
    my $strFactorCombs = "";
    ## there must be at least two factors to combine
    ## otherwise (one only) return the hash for those values
    if($numOfFactors == 1){
        foreach my $factor (@{$targets->{$iniFactor}}){
            $factorCombinations{$factor} = 1 unless ($factorCombinations{$factor});
        }
    }else{
        while(@{$factors}){
            $nxtFactor = shift(@{$factors});
            @nxtFactorValues = @{$targets->{$nxtFactor}};
            foreach my $fv1 (@iniFactorValues){
                foreach my $fv2 (@nxtFactorValues){
                    ## paste values
                    $strFactorCombs = $fv1.".".$fv2;
                    $factorCombinations{$strFactorCombs} = 1 unless ($factorCombinations{$strFactorCombs});
                }
            }
            ## make the unique keys the initial array
            @iniFactorValues = keys %factorCombinations;
        }       
    }
    ## return hash of combinations
    return(\%factorCombinations);
}

sub validateOutliers($$$){
	my ($experiment,$targets,$errors) = @_;
	## extract experiment elements: Outliers
	my @outliers = @{$experiment->{analysis}->{outliers}};
	## get list of names from targets file
	my @names = @{$targets->{name}};
    if(@outliers > 0){
        push(@{$errors},"\n       ".@outliers." Outlier(s)...");
        my $outlierNotFound = 0;
        foreach my $outlier (@outliers){
            if (!grep(/$outlier/,@names)){
            	push(@{$errors},"\n       Error: Outlier '$outlier' doesn't exist in targets file!\n");
                ##print "\n        $outlier doesn't exist in targets file!";
                $outlierNotFound+=1;
            }
        }
        if($outlierNotFound == 0){
            push(@{$errors}," OK.\n");
        }
    }else{
    	push(@{$errors},"\n       No Outliers.\n");
        ##print "\n    No Outliers.\n";
    }
}

sub validateExperimentalAnalysis($$$){
	my ($experiment,$targets,$errors) = @_;
	## extract experiment element: Analysis
	my %expAnalysis = %{$experiment->{analysis}};
	my @analysis = grep(/analysis/, keys %expAnalysis);
	# change $contrast_stringency to 0 if the contrasts being validated
	# are more complicated than a-b or a.b-c.d or (a+b)/2-(c+d)/2
	# given that that argument to the R function makeContrasts is highly
	# variable (but always a valid algebraic expression using numbers,
	# letters and the symbols (,),/,- and +) we have added this variable to play
	# with more complex expressions. Defaults to anything different to 0
	my $contrast_stringency = 1;
	my $validContrast = 0;
	## program ends if there isn't at leat one analysis
	if(@analysis < 1){
		push(@{$errors},"\n    Error: No 'analysis' to be done!");
	    ##print "\n    Error: No 'analysis' to be done!";
	    ##exit(1);
	}else{
		push(@{$errors},"\n       ".@analysis." Analysis...");
	    ##print "\n    ".@analysis." Analysis(ses)...";
	    my $analysisCount = 0;
	    ## extract targets file element: column headers
	    my @colHeaders = @{$targets->{header}};
	    my ($factorNotFound,$contrastEleNotFound,$contrastsMalformed,$descUsedAsFactor);
	    foreach my $analysis (@analysis){
	    	$factorNotFound = 0;
	    	$descUsedAsFactor = 0;
	    	$contrastEleNotFound = 0;
	    	$contrastsMalformed = 0;
	    	push(@{$errors},"\n\n       Analysis ".++$analysisCount."...");
	        ##print "\n\n        Analysis ".++$analysisCount."...";
	        ## extract experiment element: Analysis: Factors
	        my @factors = @{$experiment->{analysis}->{$analysis}->{factors}};
	        ## validate factors exist
	        foreach my $factor (@factors){
	            if (!grep(/$factor/,@colHeaders)){
	            	push(@{$errors},"\n       Error: Factor column '$factor' doesn't exist in targets file!\n");
	                ##print "\n            Error: Factor column '$factor' doesn't exist in targets file!";
	                $factorNotFound+=1;
	            }
	            if (lc($factor) eq "description"){
	            	push(@{$errors},"\n       Error: Column '$factor' cannot be used as a factor!");
	                $descUsedAsFactor+=1;	            	
	            }
	        }
	        ## can't continue if factors don't exist in targets file
	        ## or if the column 'description' has been used as a factor
	        return if(($factorNotFound)||($descUsedAsFactor));
	        ## extract experiment element: Analysis: Contrasts
	        my @constrasts = @{$experiment->{analysis}->{$analysis}->{contrasts}};
	        ## create combinations of factors: factors can be joined by dots
	        ## to form a contrast element, like the example showed a few lines ahead
	        my $factorCombinations = generateCombinations(\@factors,$targets);
	        ## validate contrasts
	        foreach my $contrast (@constrasts){
	        	$validContrast = 0;
	        	if(!$contrast_stringency){
	        		$validContrast = 1 if ($contrast =~ /-|\+|\/|\d|\(|\)| |\./g);
	        	}else{
	        		$validContrast = 1 if ($contrast =~ /^(\w+(\.\w+)*|\(\w+(\.\w+)*((\+|-)*\w+(\.\w+)*)*\)(\/[1-9]+)*)-(\w+(\.\w+)*|\(\w+(\.\w+)*((\+|-)*\w+(\.\w+)*)*\)(\/[1-9]+)*)$/);
	        	}
	        	if($validContrast){
	        		$contrast =~ s/(\/[1-9])+//g;
                    my @contrastElements = split(/-|\+/,$contrast);
                    foreach my $contrastElement (@contrastElements){
                    	$contrastElement =~ s/(\(|\))//g;
                        if(!exists $factorCombinations->{$contrastElement}){
                            push(@{$errors},"\n       Error: Contrast element '$contrastElement' in contrast '$contrast' doesn't exist in targets file!\n");
                            ##print "\n            Error: Contrast element '$contrastElement' doesn't exist in targets file!";
                            $contrastEleNotFound+=1;
                        }
                    }	        		
	        	}else{
	        		push(@{$errors},"\n       Error: Contrast '$contrast' has wrong format and can't be validated!\n");
	        		$contrastsMalformed+=1;
	        	}
	        }
	        if(($factorNotFound+$contrastEleNotFound+$contrastsMalformed)==0){
	        	push(@{$errors}," OK.");
	        }
	    }
	}	
}

sub validateExperiment($$){
    my ($experimentFile, $targetsFile) = @_;
    my $aListOfMessages = [];
    my $errorCounter = 0;
    my %errorMessage = (error_number => undef, error_message => "");
    validateOutliers($experimentFile,$targetsFile,$aListOfMessages);
    validateExperimentalAnalysis($experimentFile,$targetsFile,$aListOfMessages);
    $errorCounter = grep(/Error/, @{$aListOfMessages});
    if($errorCounter){
        unshift(@{$aListOfMessages},"\n\n$errorCounter error(s) found! Please verify your experiment file.\n");
        $errorMessage{error_number} = 1;
    }else{
        $errorMessage{error_number} = 0;
    }
    $errorMessage{error_message} = join("",@{$aListOfMessages});
    return(\%errorMessage);
}

1;

__END__

=head1 NAME

ExperimentFile.pm

=head1 SYNOPSYS

A small simple module that contains subroutines to load and validate the contents of an Experiment's YAML file.

=head1 DESCRIPTION


The Experiment's yaml file contains all the information needed to carry out a microarray data analysis. The module expects a data structure that has been created 
by the YAML::XS yaml parser and passed onto its validateExperiment subroutine which applies a series of checkings to the contents of the data structure.

If the structure of the yaml file is correct then it will only show a series of error/no error messages regarding the de information contained. If there
are errors in the structure of the YAML file itself, then the subroutines will miserably fail in trying to understand the information contained in it. 

=head1 SUBROUTINES

My super smart subroutines:

=head2 - validateExperiment($experimentFile, $targetsFile)

=over 2

A wrapper subroutine for calling specific validating subroutines. Is the entry gate which receives both the Experiment's and targets file's data structures.

=over 12

=item Type:

Function

=item Arguments:

$experimentFile: Experiment's data structure.

$targetsFile: Targets file's data structure.

=item Return:

A hash with two keys: error_number, which returns 0 in case there are no errors and 1 otherwise; and error_message, a series of error/no error messages joined together.

=back

=back

=head2 - validateExperimentalAnalysis($experiment,$targets,$errors);

=over 2

Validates the section of the Experiment's yaml file corresponding to the definition of the experimental analysis. 

=over 12

=item Type:

Procedure

=item Arguments:

$experiment: reference to the experiment's data structure.

$targets: reference to the targets file's data structure.

$errors: "by reference" variable addressing to an empty array to hold the error messages generated from the validation of the targets file's data structure.

=back

=back

=head2 - validateOutliers($experiment,$targets,$errors)

=over 2

Validates the outliers sub section of the experimental analysis definition section. 

=over 12

=item Type:

Procedure

=item Arguments:

$experiment: reference to the experiment's data structure.

$targets: reference to the targets file's data structure.

$errors: "by reference" variable addressing to an empty array to hold the error messages generated from the validation of the targets file's data structure.

=back

=back

=head2 - generateCombinations($factors,$targets)

=over 2

Generate all the possible combinations for the list of factors passed as arguments. 

=over 12

=item Type:

Function

=item Arguments:

$factors: list of factors to be combined.

$targets: reference to the targets file's data structure.

=item Return:

A hash with all the combinations obtained as keys.

=back

=back

=head1 AUTHOR

 ------------------------------------------------------------------------------
 Created at : Wellcome Trust Sanger Institute
 On         : 16/09/2010
 By         : R.E. Bautista-Garcia (rb11)
 Last update: 16/12/2013: 
              1) the yaml section for the experiment description changed from 
                 'experiment_analysis' to 'experiment'.
              2) This documentation. 
 ------------------------------------------------------------------------------

