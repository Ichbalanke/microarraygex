#!/software/bin/perl

use strict;
use warnings;
use YAML::XS qw(LoadFile);
use Cwd qw(abs_path);
use Getopt::Long;
use Pod::Usage;
use File::Basename;

use FindBin;
use lib "$FindBin::Bin/../lib";
use MicroarrayGEX;
use MicroarrayGEX::TargetsFile;
use MicroarrayGEX::ExperimentFile;
use MicroarrayGEX::InputFile qw(loadInputFiles);
use MicroarrayGEX::Publisher;

## get options
my %options = ();

# 20140123: new GetOptions
GetOptions (\%options,
	'experiment=s',
	'targets=s',
	'input=s',
	'yaml=s',
	'annotation=s',
	'sweave!',
	'help',
	'manual') or pod2usage(1);

# 20140123: new options definition method
pod2usage(2) if $options{'help'};
pod2usage(-exitval => 0, -verbose => 2) if $options{'manual'};

## get experiment id
my $experimentId = $options{'experiment'} || (print("Missing experiment name.\n\n") && pod2usage(2));
## get targets file
my $targetsFileName = $options{'targets'} || (print("Missing targets file.\n\n") && pod2usage(2));
## get input file
my $inputFileName = $options{'input'} || (print("Missing input file.\n\n") && pod2usage(2));
## get annotation file
my $annotationFileName = $options{'annotation'} // "";
## get yaml file
my $yamlFileName = $options{'yaml'} || (print("Missing YAML file.\n\n") && pod2usage(2));
## option to evaluate the Sweave document or not
my $sourceSweave = $options{'sweave'} // 1;
## get help
my $help;
## get even more help
my $man;

# 20140123: to get default values, do this:
##----------------------------#
## validate files paths       #
##----------------------------#
if(!-e $yamlFileName){
	die "Yaml file $yamlFileName could not be found in the path specified.\n";
}
if(!-e $inputFileName){
	die "Sample Probe Profile $inputFileName could not be found in the path specified.\n";
}
if(!-e $targetsFileName){
	die "Targets file $targetsFileName could not be found in the path specified.\n";
}

if( ($annotationFileName) && (!-e $annotationFileName) ){
	die "Annotation file $annotationFileName could not be found in the path specified.\n";
}

##----------------------------#
## read yaml file             #
##----------------------------#
my $experimentYaml = LoadFile($yamlFileName);

## file stem
my $expExperiment = $experimentYaml->{experiment}->{name};

($expExperiment eq $experimentId) or die "\nArgument experiment id not equal to experiment id in .yml file!\n";

print "\nProcessing: $expExperiment ...\n";

##----------------------------#
## validate input files       #
##----------------------------#

print "\nChecking input file(s)...";

## we need a hash to hold the error message 
## from the validation subroutines
my $inputfilerrors = {};
## also a list of the least of annotation columns that must be present
## in at least one of the sample probe file or the annotation file
## potentially to be set in a separate config file (like a yaml file)
my %defaultAnnotationCols = ('PROBE_ID'=>1
	,'PROBE_SEQUENCE'=>1
	,'CHROMOSOME'=>1
	,'PROBE_COORDINATES'=>1
);

MicroarrayGEX::InputFile::loadInputFiles($inputFileName,$annotationFileName,\%defaultAnnotationCols,$inputfilerrors);

## program ends if there's a problem with the input file(s)
if($inputfilerrors->{error_number}){
	print $inputfilerrors->{error_message};
	exit(1);
}else{
	print " Done. No errors found.\n";
}

##----------------------------#
## validate targets file      #
##----------------------------#

print "\nChecking targets file...";

## we need a hash to hold the error message 
## from the validation subroutines
my $targetserrors = {};
my $hRefTargets = MicroarrayGEX::TargetsFile::loadTargets($targetsFileName, $inputFileName, $targetserrors);

## program ends if there's a problem with the targets file
if($targetserrors->{error_number}){
	print $targetserrors->{error_message};
	exit(1);
}else{
	print " Done. No errors found.\n";
}


##----------------------------#
## validate experiment's info #
##----------------------------#

print "\nChecking experiment's file...";

## we need a hash to hold the error message 
## from the validation subroutines
my $experimenterrors = {};
$experimenterrors = MicroarrayGEX::ExperimentFile::validateExperiment($experimentYaml, $hRefTargets);

## program ends if there's a problem with the experiment's file
if($experimenterrors->{error_number}){
	print $experimenterrors->{error_message};
	exit(1);
}else{
	print " Done.No errors found.\n";
}

#my $inputFileName = ${$hRefTargets->{fileName}}[0];
##------------------------------#
## generate directory structure #
##------------------------------#
print "\nCreating directory structure...";
`mkdir -p $expExperiment/input $expExperiment/output $expExperiment/resources $expExperiment/QC $expExperiment/log`;

## obtain differential expression analyses from experiment's yaml
my %expAnalyses = %{$experimentYaml->{analysis}};
my @analysis = grep(/analysis/, keys %expAnalyses);
my $analysisSubdir = "";

## the next loop reads in the experiment's yaml file each of
## the DE analyses (keys 'analysis[X]:') and creates its own dir
if (scalar @analysis > 1){
	foreach my $analysis (@analysis){
		$analysisSubdir = $analysis."/";
		`mkdir -p $expExperiment/output/$analysis`;
	}	
}

print " Done.\n";

##--------------#
## outliers
##--------------#
my @outliers = map("\"".$_."\"",@{$experimentYaml->{experiment_analysis}->{outliers}});

##----------------------------#
## generate R script file     #
##----------------------------#
print "\nGenerating R script file...";

MicroarrayGEX::Publisher::rScript($experimentYaml);

print " Done.\n";

##----------------------------#
## generate sweave file       #
##----------------------------#
print "\nGenerating Sweave file...";

MicroarrayGEX::Publisher::sweaveDocument($experimentYaml, $inputFileName);

print " Done.\n";

##----------------------------#
## generate wrapper script    #
##----------------------------#
print "\nGenerating wrapper script...";

my $absPath = abs_path();

MicroarrayGEX::Publisher::sweaveWrapper($experimentYaml, $absPath);

print " Done.\n";

##--------------------------#
## handle outliers' files   #
##--------------------------#

## if there are outliers defined
## try to find previous runs output files (from the R script)
## and copy them into a new directory
if(@outliers>0){
	print "\nExperiment with Outliers, backing up old output files into $expExperiment/output.outliers/...";
	`mkdir -p $expExperiment/output.outliers`;
	`find $expExperiment/output -name "diff_gene_expression*.txt" | xargs -I {} cp {} ./$expExperiment/output.outliers/`;
	print " Done.\n";
}

##------------------------------#
## generate directory structure #
##------------------------------#
print "\nMoving/Copying files into resources directory...";
`cp $targetsFileName $expExperiment/resources/`;
`cp $inputFileName $expExperiment/input/`;
`cp $yamlFileName $expExperiment/resources/`;
#`mv sweave_wrapper.sh $expExperiment/resources/`;
print " Done.\n";

##----------------------------#
## source sweave file         #
##----------------------------#
if ($sourceSweave) {
	my $bsubcommand = "bsub ";
	$bsubcommand .= "-o $expExperiment/wrapperlog.out ";
	$bsubcommand .= "-e $expExperiment/wrapperlog.err ";
	$bsubcommand .= "-R'select[mem>1900] rusage[mem=1900]' ";
	$bsubcommand .= "-M1900 ";
	$bsubcommand .= "$expExperiment/sweave_wrapper.sh";
	print "\nExecuting Sweave wrapper file on LSF. Use bjobs to see its progress.\n";
	
	system($bsubcommand); #, $outputarg, $errorargs, $memoryneed, $resourcearg, $memoryarg, $rcommand, $sweavedocument);
	
	if ($? == -1) {
		print "\nFailed to execute!: $!\n";
    }elsif ($? & 127) {
    	printf "\nChild died with signal %d, %s coredump\n", ($? & 127), ($? & 128) ? 'with' : 'without';
    }if ($? == 0) {
    	print "";
    }else{
    	printf "\nSomething's awry, child exited with value %d\n", $? >> 8;
    }
}else{
	print "\nINFO: You chose not to execute the Sweave file, use 'imgex_analysis.pl --manual' to learn how to do it manually.";
}

##----------------------------#
## generate wiki file         #
##----------------------------#

#print "\nGenerating wiki page file...";

#my $wikiYaml = LoadFile('../yaml/wiki.yml');

#Publisher::wikiPage($experimentYaml, $hRefTargets, $wikiYaml, $targetsFileName, $inputFileName);

#print " Done.\n";

##----------------------------#
## generate markup file       #
##----------------------------#

#print "\nGenerating markup file...";

#my $infoYaml = LoadFile('../yaml/info.yml');

#Publisher::xmlMarkup($experimentYaml, $hRefTargets, $r_scriptYaml, $infoYaml, $targetsFileName);

#print " Done.\n";
print "\nINFO: In case outlier arrays are found use 'imgex_analysis.pl --manual' to learn how to redo the analysis.";

print "\n\nFinished! Remember to wait for the LSF job to finish (use bjobs).\n";

__END__

=head1 NAME

imgex_analysis - Analysis of Illumina gene expression microarray data.

=head1 SYNOPSIS

imgex_analysis.pl [arguments]

Required arguments:

   --experiment=[experiment name]
   --targets=[targets file]
   --input=[sample probe profile file]
   --yaml=[experiment yaml file]
    
Optional arguments:
    
   --annotation=[annotation file]  If the annotation file is provided.
   --nosweave                      If the Sweave file should not be evaluated (run manually)

To obtain help use either of these:

   --help     This help, or
   --manual   Verbose help

=head1 ARGUMENTS

=over 8

=item B<--experiment>

Required. Name of the experiment in the format experiment_name_yyyy-mm-dd.

=item B<--targets>

Required. Targets file, contains the list of arrays to be processed and information needed for the differential expression analysis (contrasts).

=item B<--input>

Required. Input file (sample probe profile) containing the expression data.

=item B<--yaml>

Required. File in YAML format containing specifications of the experiment and the analysis.

=item B<--annotation>

Optional. The annotation file is needed only if it hasn't been included in the input file.

=item B<--sweave/--nosweave>

Optional. Default is --sweave. Use --nosweave to tell the program not to evaluate the Sweave file (R code + analysis documentation), in which case it will need to be done manually via an R session or R CMD BATCH after the program finishes. 

=back

=head1 DESCRIPTION

B<imgex_analysis.pl> will allow you to run a full analysis of Illumina gene expression microarray data. The specification of the analysis is described inside a YAML file (the experiment YAML file). Various inputs are required to execute the analysis.

Once the inputs have been checked for completeness and correctness (not completely infallible) various outputs are created, principally a pure R script and a Sweave document. The latter is sourced by default in order to execute the DE analysis.

All inputs and outputs are saved in a bespoke directory named as especified by the argument --experiment.

=head2 Sweave execution

Unless you had used the --nosweave option, a Sweave(sweavedocument.Rnw) command will be executed for you automatically by imgex_analysis.pl using the LSF platform. This means a bsub job has been created and you will need to wait for its completion for you to be able to see the final PDF report of the analysis.

In previous versions of the program, after all the files and directories had been created you were required to open an R session and manually execute the '.R' script generated for you. Additionally you were required to publish the results online in a Wiki style and then copy/move the files to their final destination.

Since the decommissioning of the Wiki server a new way to deliver the results of the analysis had to be found. That new way is a PDF report generated by Sweave. Sweave combines the R script execution with the delivery of results in one file, the '.Rnw' file.

After imgex_analysis has finished running you need to wait until LSF have finished executing the Sweave file. Use the following command to explore the status of the job:

$> bjobs

Which will output something similar to this:

JOBID   USER    STAT  QUEUE      FROM_HOST   EXEC_HOST   JOB_NAME   SUBMIT_TIME
9770642 rb11    PEND  normal     bc-20-1-14              *01-16.Rnw Jan 27 17:16

In this case the status of the job (column STAT) indicates it's PENDing. Succesive calls to bjobs will show different status, most importantly: RUN. Even later on, once the job has completed if you call again the bsub command you will see the message:

$> No unfinished job found

Which means the job has finished and the PDF document should be ready. Look for it inside the project directory and point the customer to it as the starting point for their review of the results.

The final step for you will be to copy/move the project and all of its data to its final destination and similarly point the customer to it. Future versions of the program will do this automatically.

=head2 Manually execute Sweave

To manually execute the Sweave document you have two options:

1) Open an interactive R session (by typing R in the command line inside the project directory) and run the following command, indicating the name of the .Rnw file:

R> Sweave(sweavedocument.Rnw) 

2) Run R in batch mode (prefered). To do this you need to use LSF and although it's a long command you only need to copy/paste B<>in-a-single-line> (i.e. no new lines in between) and replace the name of the .Rnw file. Do this inside the project directory:

$> bsub -o bsuboutput.o -e bsuberror.e -R'select[mem>2900] rusage[mem=2900]' -M2900 ./sweave_wrapper.sh

This will create an LSF job that you can inspect using the method described above. Once that is finished you will have a PDF file with all the information regarding the analysis. After that follow the instructions in the previous section as to how to deliver the results.

=head2 Outliers

Outlier arrays can only be discovered after the analysis has been done. Once they have been identified add them to the experiment's YAML file and run this program again. 

The list of outliers can be entered as a dashed list of items:

- 1234567890_A
- 2345678901_B

Or as a single dashed item with the list of arrays separated by comas and enclosed in square brackets:

- [1234567890_A, 2345678901_B]

Don't forget to leave the necessary spaces (no tabs) before the '-'.

=head1 AUTHOR

Ruben Bautista (rb11@sanger.ac.uk)

=head1 COPYRIGHT

Copyright (C) 2014 Genome Research Ltd (GRL) by Ruben E. Bautista-Garcia

=cut