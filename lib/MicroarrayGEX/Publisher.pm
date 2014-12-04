package MicroarrayGEX::Publisher;

use 5.013;
use strict;
use warnings;
use File::Basename;
use YAML::XS qw(LoadFile 
                Load);
use File::Slurp qw(slurp);
use Date::Calc qw(Add_Delta_YM);
use File::Share ':all';

our (@ISA, @EXPORT, @EXPORT_OK, $VERSION);

use Exporter;

$VERSION = 0.01;
@ISA = qw(Exporter);
@EXPORT = qw();

sub readYamlFile($) {
	my $yamlFile = shift(@_);
	my $poo = $INC{'MicroarrayGEX.pm'} ;
    my $data_location = dist_file('MicroarrayGEX', $yamlFile);
    my $data = LoadFile($data_location);
    return($data); 
}

sub rScript($){
	#my ($experimentYaml, $r_scriptYaml) = @_;
	my ($experimentYaml) = shift(@_);
	## get r script yaml data
	my $r_scriptYaml = readYamlFile('r_script.yml');
	## file name
	my $expExperiment = $experimentYaml->{experiment}->{name};
	## chunck of code
	my $codeChunk = "";
	## create R script file:
	my $r_script_file = $expExperiment."/".$expExperiment.".R";
	open FH_RSCRIPT, ">$r_script_file" or die "file $r_script_file could not be created\n";
	
	$codeChunk = rCodeFormatter($experimentYaml, $r_scriptYaml, 'hdr_libraries_functions');
	print FH_RSCRIPT $codeChunk;
		
	$codeChunk = rCodeFormatter($experimentYaml, $r_scriptYaml, 'stmt_function_qcreport');
	print FH_RSCRIPT $codeChunk;

	$codeChunk = rCodeFormatter($experimentYaml, $r_scriptYaml, 'stmt_input');
	print FH_RSCRIPT $codeChunk;
		
	$codeChunk = rCodeFormatter($experimentYaml, $r_scriptYaml, 'stmt_qc');
	print FH_RSCRIPT $codeChunk;

	$codeChunk = rCodeFormatter($experimentYaml, $r_scriptYaml, 'stmt_qc_report_rscript');
	print FH_RSCRIPT $codeChunk;

	$codeChunk = rCodeFormatter($experimentYaml, $r_scriptYaml, 'cmnt_analysis');
	print FH_RSCRIPT $codeChunk;

	## close file
	close(FH_RSCRIPT);	
}

sub sweaveDocument($$){
	#my ($experimentYaml, $r_scriptYaml, $sweaveYaml, $inputFileName) = @_;
	my ($experimentYaml, $inputFileName) = @_;
	
	## yaml file data
	my $sweaveYaml = readYamlFile('sweave.yml');
	my $r_scriptYaml = readYamlFile('r_script.yml');
	## chuncks of code
	my $sweaveChunk = "";
	my $rCodeChunk = "";
	
	## get experiment's values
	# experiment name:
	my $experiment = $experimentYaml->{experiment}->{name};
	my $formattedExperiment = $experiment;
	$formattedExperiment =~ s/\_/\\\_/g;
	# overview
	my $overview = $experimentYaml->{experiment}->{overview};
	$overview =~ s/\_/\\\_/g;
	# organism:
	my $organism = ucfirst($experimentYaml->{experiment}->{organism});
	# experimental designs (analyses)
	my %analyses = %{$experimentYaml->{analysis}};
	my @analysis = grep(/analysis/, keys %analyses);
	my $analysisName = "";
	my $analysisSubdir = "";
	# people info:
	my $analystUser = $experimentYaml->{experiment}->{analyst}->{user};
	my $analystName = $experimentYaml->{experiment}->{analyst}->{name};
	my $investigatorUser = $experimentYaml->{experiment}->{investigator}->{user};
	my $investigatorName = $experimentYaml->{experiment}->{investigator}->{name};
	# outliers
	my @outliers = map("\"".$_."\"",@{$experimentYaml->{analysis}->{outliers}});
	# sample set name:
	my $sampleSetName = $experimentYaml->{analysis}->{sample_set_name};
	# sweave arguments: extract various values from the sweave yaml file
	my $arrayBeadchipLink = "";
	my $arrayBeadchipName = "";
	# illumina software:
	my $extractionSoftwareLink = $sweaveYaml->{arguments}->{extraction_software_link};
	my $extractionSoftwareName = $sweaveYaml->{arguments}->{extraction_software_name};
	# get file name of input file
	my($filename, $directories, $suffix) = fileparse($inputFileName);
	$filename =~ s/\_/\\\_/g;
	
	## create Sweave document file:
	my $sweave_file = $experiment."/".$experiment.".Rnw";
	open FH_SWEAVE, ">$sweave_file" or die "file $sweave_file could not be created\n";

	## start writing sweave document
	
	##I. obtain tex code for the main body of the document
	$sweaveChunk = $sweaveYaml->{tex_main_text};	
	#1. obtain r code for each r section and replace accordingly:
	#   - libraries and functions:
	$rCodeChunk = rCodeFormatter($experimentYaml, $r_scriptYaml, 'hdr_libraries_functions');
	chomp($rCodeChunk);
	$sweaveChunk =~ s/<libs_funcs>.*<\/libs_funcs>/$rCodeChunk/g;
	#   - input:
	$rCodeChunk = rCodeFormatter($experimentYaml, $r_scriptYaml, 'stmt_input');
	chomp($rCodeChunk);
	$sweaveChunk =~ s/<inputcode>.*<\/inputcode>/$rCodeChunk/g;
	#   - qc
	$rCodeChunk = rCodeFormatter($experimentYaml, $r_scriptYaml, 'stmt_qc');
	$sweaveChunk =~ s/<qc>.*<\/qc>/$rCodeChunk/g;
	#   - qc report:
	$rCodeChunk = rCodeFormatter($experimentYaml, $r_scriptYaml, 'stmt_qc_report_sweave');
	chomp($rCodeChunk);
	$sweaveChunk =~ s/<qcreport>.*<\/qcreport>/$rCodeChunk/g;
	#2. select array beadchip
	if(uc($organism) eq "MOUSE"){
		$arrayBeadchipLink = $sweaveYaml->{arguments}->{mouse_array_link};
		$arrayBeadchipName = $sweaveYaml->{arguments}->{mouse_array_name};
	}elsif(uc($organism) eq "HUMAN"){
		$arrayBeadchipLink = $sweaveYaml->{arguments}->{human_array_link};
		$arrayBeadchipName = $sweaveYaml->{arguments}->{human_array_name};
	}
	#3. replace other tags with formatted info
	#   - replace tags:
	$sweaveChunk =~ s/<experiment>.*<\/experiment>/$experiment/g;
	$sweaveChunk  =~ s/<overview>.*<\/overview>/$overview/g;
	$sweaveChunk  =~ s/<investigatorname>.*<\/investigatorname>/$investigatorName/g;
	$sweaveChunk =~ s/<formattedexperiment>.*<\/formattedexperiment>/$formattedExperiment/g;
	$sweaveChunk  =~ s/<raw_data_file>.*<\/raw_data_file>/$filename/g;
	$sweaveChunk  =~ s/<array_link>.*<\/array_link>/$arrayBeadchipLink/g;
	$sweaveChunk  =~ s/<array_name>.*<\/array_name>/$arrayBeadchipName/g;
	$sweaveChunk  =~ s/<sample_set_name>.*<\/sample_set_name>/$sampleSetName/g;
	$sweaveChunk =~ s/<analyst_user>.*<\/analyst_user>/$analystUser/g;
	$sweaveChunk =~ s/<analyst_name>.*<\/analyst_name>/$analystName/g;
	$sweaveChunk =~ s/<extraction_software_link>.*<\/extraction_software_link>/$extractionSoftwareLink/g;
	$sweaveChunk =~ s/<extraction_software_name>.*<\/extraction_software_name>/$extractionSoftwareName/g;
	#3. print what we have so far
	print FH_SWEAVE $sweaveChunk."\n\n";	
	
	##II. obtain tex code for the qc part of the document
	#1. clean up the variable that holds the tex code
	$sweaveChunk = "";
	#2. loop through the list of qc plots and generate the r code for each
	my @lumiObjectTypes = ('Raw', 'Normalised');
	foreach my $lumiObjType (@lumiObjectTypes){
		# - read in the tex code:
		my $sweaveChunkQC = $sweaveYaml->{tex_qcreports}."\n\n";
		my $qcPlotsLine = "";
		foreach my $qcplot (@{$sweaveYaml->{arguments}->{qcplots}}){
			# - read in the r code:
			my $sweaveChunkR = $sweaveYaml->{rcode_qcplots}."\n\n";
			# - replace the info for the plot code:
			$sweaveChunkR =~ s/<lumiobjecttype>.*<\/lumiobjecttype>/$lumiObjType/g;
			$sweaveChunkR =~ s/<whatplot>.*<\/whatplot>/$qcplot/g;
			# - concatenate multiple plot code lines
			$qcPlotsLine = $qcPlotsLine.$sweaveChunkR;
		}
		# - replace info for the tex code
		$sweaveChunkQC =~ s/<lumiobjecttype>.*<\/lumiobjecttype>/$lumiObjType/g;
		$sweaveChunkQC =~ s/<rcodeqcplots>.*<\/rcodeqcplots>/$qcPlotsLine/g;
		# - concatenate tex code lines for raw and norm qc plots:
		$sweaveChunk = $sweaveChunk.$sweaveChunkQC."\n\n";
	}
	#3. print it to the file
	print FH_SWEAVE $sweaveChunk;
	
	##III. QC outliers section if exists
	if(scalar @outliers>0){
		#1. get list of outliers from experiment
	    my $textOutliersList = join(", ", @{$experimentYaml->{analysis}->{outliers}});
	    #2. read in the tex code:
	    $sweaveChunk = $sweaveYaml->{tex_results_outliers}."\n";
	    #3. format code
	    $sweaveChunk =~ s/<outliers>.*<\/outliers>/$textOutliersList/g;
		#2. print it to the file
		print FH_SWEAVE $sweaveChunk;
	}

	##IV. obtain tex code for results	
	$sweaveChunk = $sweaveYaml->{tex_results}."\n";
	#1. replace r code for diff. expr. analysis
	$rCodeChunk = rCodeFormatter($experimentYaml, $r_scriptYaml, 'cmnt_analysis');
	chomp($rCodeChunk);
	$sweaveChunk =~ s/<analyses>.*<\/analyses>/$rCodeChunk/g;
	#2. print it to file
	print FH_SWEAVE $sweaveChunk."\n";
	
	##V. obtain tex code for analyses output files
	my @outputFileTypes = ('filtered', 'unfiltered');
	$sweaveChunk = "";
		
	foreach my $analysis (@analysis){
	    my @constrasts = @{$experimentYaml->{analysis}->{$analysis}->{contrasts}};
	    $analysisName = $experimentYaml->{analysis}->{$analysis}->{name};
	    chomp($analysisName);
	    my $analysisOutput = $sweaveYaml->{tex_output_title};
	    ## if only one analysis the default directory is 'output'
	    ## otherwise assign a new one named as the key of this analysis
	    if (scalar @analysis > 1){
	        $analysisSubdir = $analysis."/";
	    }
	    my $contrastDataOutput = "";
	    foreach my $contrast (@constrasts){
	    	#my $contrastDataOutput = "";
	    	my @contrastParts = split("-",$contrast);
	    	my $formattedContrastItem = $contrastParts[0]." vs ".$contrastParts[1];
	    	$formattedContrastItem =~ s/\_/\\\_/g;
	    	foreach my $outputFileType (@outputFileTypes){
	    		# read in a fresh one per each contrast per type of file
				my $contrastDataOutputItem = $sweaveYaml->{tex_output_files};
		    	## format contrasts
		    	my $formattedContrastFile = $contrast;
		    	$formattedContrastFile =~ s/\///g;
	        	$contrastDataOutputItem =~ s/<formattedcontrastitem>.*<\/formattedcontrastitem>/$formattedContrastItem/g;
	        	$contrastDataOutputItem =~ s/<analysissubdir>.*<\/analysissubdir>/$analysisSubdir/g;
	        	$contrastDataOutputItem =~ s/<formattedcontrastfile>.*<\/formattedcontrastfile>/$formattedContrastFile/g;
	        	$contrastDataOutputItem =~ s/<outputfiletypefile>.*<\/outputfiletypefile>/$outputFileType/g;
	        	$contrastDataOutputItem =~ s/<outputfiletypedesc>.*<\/outputfiletypedesc>/$outputFileType/g;
		        $contrastDataOutput = $contrastDataOutput.$contrastDataOutputItem."\n\n";
	    	}
	    }
	    $analysisOutput =~ s/<analysisoutput>.*<\/analysisoutput>/$contrastDataOutput/g;
	    $analysisOutput =~ s/<analysisname>.*<\/analysisname>/$analysisName/g;
	    $sweaveChunk = $sweaveChunk.$analysisOutput."\n";
	}
	$sweaveChunk = $sweaveChunk."\n";
	print FH_SWEAVE $sweaveChunk."\n"."\\end{document}";
	
	close FH_SWEAVE;
}

sub sweaveWrapper($$){
	my ($experimentYaml, $absPath) = @_;

	## get experiment's values
	# file stem
	my $experiment = $experimentYaml->{experiment}->{name};

	my $sweaveWrapperFile = $experiment."/sweave_wrapper.sh";
	open FH_SW, ">$sweaveWrapperFile" or die "file sweave_wrapper.sh could not be created\n";
	
	print FH_SW qq<#!/bin/bash\n\ncd $experiment\n\necho Ready to run Sweave then pdflatex...\n\n>;
	print FH_SW qq<cd $absPath/$experiment/\n\n>;
	print FH_SW qq</software/R-3.0.0/bin/R CMD Sweave $experiment.Rnw && pdflatex -interaction=nonstopmode $experiment.tex && pdflatex -interaction=nonstopmode $experiment\n\n>;
	print FH_SW qq<echo\necho Cleaning up...\n\n>;
	print FH_SW qq<mv *.log *.out *.aux *.tex *.toc log/\n>;
	#print FH_SW qq<mv *qc*pdf QC/\n\necho\necho Done!>;
	
	close FH_SW;
	
	system("chmod u+x $sweaveWrapperFile");
}

sub wikiPage($$$$$){
	my ($experimentYaml, $hRefTargets, $wikiYaml, $targetsFileName, $inputFileName) = @_;
	
	## get experiment's values
	# file stem
	my $expExperiment = $experimentYaml->{experiment}->{name};
	my $expOrganism = ucfirst($experimentYaml->{experiment}->{organism});
	# experimental designs (analysis)
	my %expAnalyses = %{$experimentYaml->{analysis}};
	my @analysis = grep(/analysis/, keys %expAnalyses);
	# outliers
	my @outliers = map("\"".$_."\"",@{$experimentYaml->{analysis}->{outliers}});
	
	## Define variables
	my $analysisName = "";
	my $analysisSubdir = "";
	my $makeSubdirs = 0;
	$makeSubdirs = 1 if (scalar @analysis>1);
	# name the wiki page file
	my $wiki_file = $expExperiment."/".$expExperiment.".wiki";
		 
	open FH_WIKI, ">$wiki_file" or die "file $wiki_file could not be created\n";
	
	my $wikiMainText = $wikiYaml->{main_text};
	my $wikiSite = $wikiYaml->{arguments}->{wiki_site};
	my $textOutliersList = "";
	my $wikiResultsOutliers = "";
	my $wikiQCOutliers = "";
	my $wikiRemOutliers = "";
	my $wikiArrayBeadchipLink = "";
	my $wikiArrayBeadchipName = "";
	my $expDate = get_timestamp();
	my $expOverview = $experimentYaml->{experiment}->{description};
	my $expSampleSetName = $experimentYaml->{analysis}->{sample_set_name};
	my $expAnalystUser = $experimentYaml->{experiment}->{analyst}->{user};
	my $expAnalystName = $experimentYaml->{experiment}->{analyst}->{name};
	my $expInvestigatorUser = $experimentYaml->{experiment}->{investigator}->{user};
	## select array beadchip
	if(uc($expOrganism) eq "MOUSE"){
		$wikiArrayBeadchipLink = $wikiYaml->{arguments}->{mouse_array_link};
		$wikiArrayBeadchipName = $wikiYaml->{arguments}->{mouse_array_name};
	}elsif(uc($expOrganism) eq "HUMAN"){
		$wikiArrayBeadchipLink = $wikiYaml->{arguments}->{human_array_link};
		$wikiArrayBeadchipName = $wikiYaml->{arguments}->{human_array_name};
	}
	my $wikiArrayBeadchip = "[$wikiArrayBeadchipLink $wikiArrayBeadchipName]";
	## workout output files
	my ($wikiDataOutputFil,$wikiDataOutputUnf,$wikiDataOutput);
	my $wikiDataOutputFinal = "";
	my $formatContrast;
	my @contrastParts;
	foreach my $analysis (@analysis){
	    my @constrasts = @{$experimentYaml->{analysis}->{$analysis}->{contrasts}};
	    $analysisName = $experimentYaml->{analysis}->{$analysis}->{name}; 
	    $wikiDataOutputFinal = $wikiDataOutputFinal."\n;".$analysisName;
	    ## if we have more than one analysis
	    ## the flag $makeSubdirs has been set earlier
	    $analysisSubdir = $analysis."/" if($makeSubdirs);
	    foreach my $contrast (@constrasts){
	    	## a fresh one per each contrast
	    	$wikiDataOutputUnf = $wikiYaml->{data_output_unfiltered};
	    	$wikiDataOutputFil = $wikiYaml->{data_output_filtered};
	    	$wikiDataOutput = " ".$wikiDataOutputUnf."\n ".$wikiDataOutputFil;
	    	## at this point of the program we can do this safely
	    	## because they've been validated before
	    	#@contrastParts = /\(.*?\)|[^\(\)-\+]+/g;
			@contrastParts = ();
	    	@contrastParts = split("-",$contrast);			
			# groups the phrase inside the quotes
			#push(@contrastParts, $+) while $contrast =~ m{\(([^\(\)\\]*(?:\\.[^\(\)\\]*)*)\)-?|([^-]+)-?|-}gx;
			#push(@contrastParts, undef) if substr($contrast,-1,1) eq '-';
	    	## format contrasts
	    	$formatContrast = "[".$contrastParts[0]."] vs [".$contrastParts[1]."]";
	        $wikiDataOutput =~ s/<formatted_contrast>.*<\/formatted_contrast>/$formatContrast/g;
	        $wikiDataOutput =~ s/<contrast>.*<\/contrast>/$contrast/g;
	        $wikiDataOutput =~ s/<analysis_subdir>.*<\/analysis_subdir>/$analysisSubdir/g;
	        $wikiDataOutput = sprintf("%*s", 1, $wikiDataOutput);
	        $wikiDataOutputFinal = $wikiDataOutputFinal."\n".$wikiDataOutput."\n ";
	    }
	    $wikiDataOutputFinal =~ s/ $//;
	    $wikiDataOutputFinal = $wikiDataOutputFinal."\n";
	}
	##targets file exists as a hash, we'll use that hash to format the output
	my $colsep = '     ';
	my $offsetchar = " ";
	my $offsetnum = 1;
	my $deleteFileNameCol = 1;
	my $targetsText = formatTargetsOutput($hRefTargets,$targetsFileName,$deleteFileNameCol,$colsep, $offsetchar,$offsetnum);
	## get all outliers sections
	if(@outliers>0){
	    $textOutliersList = join(", ", @{$experimentYaml->{analysis}->{outliers}});
	    $wikiResultsOutliers = $wikiYaml->{results_outliers}."\n\n";
	    $wikiQCOutliers = "\n".$wikiYaml->{qc_outliers};
	    $wikiRemOutliers = $wikiYaml->{arguments}->{remOutliers_fileSufix};
	}
	## QC outliers section if exists
	$wikiMainText = $wikiMainText.$wikiQCOutliers;
	## add results section
	$wikiMainText = $wikiMainText."\n".$wikiYaml->{results};
	## and results_outliers section if exists
	$wikiMainText = $wikiMainText."\n\n".$wikiResultsOutliers;
	## add output files text
	$wikiMainText = $wikiMainText.$wikiDataOutputFinal;
	## and we're ready to insert and wash the tags off from main text
	## substiting them with the information we have
	$wikiMainText  =~ s/<array_link_name>.*<\/array_link_name>/$wikiArrayBeadchip/g;
	$wikiMainText  =~ s/<targets_file>.*<\/targets_file>/$targetsText/g;
	$wikiMainText  =~ s/<wiki_site>.*<\/wiki_site>/$wikiSite/g;
	$wikiMainText  =~ s/<experiment_dir>.*<\/experiment_dir>/$expExperiment/g;
	$wikiMainText  =~ s/<experiment>.*<\/experiment>/$expExperiment/g;
	$wikiMainText  =~ s/<date>.*<\/date>/$expDate/g;
	$wikiMainText  =~ s/<overview>.*<\/overview>/$expOverview/g;
	$wikiMainText  =~ s/<sample_set_name>.*<\/sample_set_name>/$expSampleSetName/g;
	$wikiMainText  =~ s/<raw_data_file>.*<\/raw_data_file>/$inputFileName/g;
	$wikiMainText  =~ s/<analyst_user>.*<\/analyst_user>/$expAnalystUser/g;
	$wikiMainText  =~ s/<analyst_name>.*<\/analyst_name>/$expAnalystName/g;
	$wikiMainText  =~ s/<investigator_user>.*<\/investigator_user>/$expInvestigatorUser/g;
	$wikiMainText  =~ s/<outliers>.*<\/outliers>/$textOutliersList/g;
	$wikiMainText  =~ s/<remOutliers_fileSufix>.*<\/remOutliers_fileSufix>/$wikiRemOutliers/g;
	## finally, print to file
	print FH_WIKI $wikiMainText;
	
	close FH_WIKI;
	
}

sub xmlMarkup($$$$$){
	my ($experimentYaml, $hRefTargets, $r_scriptYaml, $infoYaml, $targetsFileName) = @_;
	
	## file stem
	my $expExperiment = $experimentYaml->{experiment}->{name};
	
	## name the markup file:
	my $markup_file_out = $expExperiment."/".$expExperiment.".xml";
	open FH_MARKUP, ">$markup_file_out" or die "file $markup_file_out could not be created\n";
	
	## slurp the contents of markup.txt to replace text
	my $markup_file_in = "../yaml/markup.txt";
	my $markup_file_text = File::Slurp::read_file($markup_file_in);
	
	## get all the values needed:
	my $expName = $expExperiment;
	my $offsetchar = "	";
	my $offsetnum = 10;
	my $deleteFileNameCol = 1;
	my $colsep = "	";
	my $expDesign = formatTargetsOutput($hRefTargets,$targetsFileName,$deleteFileNameCol,$colsep,$offsetchar,$offsetnum);
	my $expDate = $experimentYaml->{experiment}->{date};
	my $expOverview = $experimentYaml->{experiment}->{description};
	my $expIUser = $experimentYaml->{experiment}->{investigator}->{user};
	my $expIName = $experimentYaml->{experiment}->{investigator}->{name};
	my $expIMail = $experimentYaml->{experiment}->{investigator}->{mail};
	my $expAUser = $experimentYaml->{experiment}->{analyst}->{user};
	my $expAName = $experimentYaml->{experiment}->{analyst}->{name};
	my $expAMail = $experimentYaml->{experiment}->{analyst}->{mail};
	my $expLUser = $experimentYaml->{experiment}->{laboratory}->{user};
	my $expLName = $experimentYaml->{experiment}->{laboratory}->{name};
	my $expLMail = $experimentYaml->{experiment}->{laboratory}->{mail};
	my $expSampleSetName = $experimentYaml->{analysis}->{sample_set_name};
	my $analysisDescription = $infoYaml->{analysis_info}->{analysis_description};
	my ($year, $month, $day) = split("-",$expDate);
	my ($year2, $month2, $day2) = Add_Delta_YM($year, $month, $day, 2, 0);
	my $datePurge = join("-",($year2, $month2, $day2));
	my $rawQCfileName = $expExperiment."_raw_qc.pdf";
	my $normQCfileName = $expExperiment."_qnorm_qc.pdf";
	my $qcDescription = $infoYaml->{results_info}->{qc_description};
	my %expAnalyses = %{$experimentYaml->{analysis}};
	my @analysis = grep(/analysis/, keys %expAnalyses);
	my $expComparisons = "";
	my $formatContrast;
	my @contrastParts;
	foreach my $analysis (@analysis){
	    my @constrasts = @{$experimentYaml->{analysis}->{$analysis}->{contrasts}};
	    foreach my $contrast (@constrasts){
	    	@contrastParts = ();
			 # groups the phrase inside the quotes
			push(@contrastParts, $+) while $contrast =~ m{\(([^\(\)\\]*(?:\\.[^\(\)\\]*)*)\)-?|([^-]+)-?|-}gx;
			push(@contrastParts, undef) if substr($contrast,-1,1) eq '-';
	    	## format contrasts
	    	$formatContrast = $contrastParts[0]." vs ".$contrastParts[1]."\tfiltered\tunfiltered";
	    	$expComparisons = $expComparisons.$formatContrast."\n";
	    }
	    $expComparisons =~ s/ $//;
	    $expComparisons = $expComparisons."\n";
	}
    my $resultsDescP1 = $infoYaml->{results_info}->{results_description}->{P1};
	my $resultsDescP2 = $infoYaml->{results_info}->{results_description}->{P2};
	my $resultsDescP3 = $infoYaml->{results_info}->{results_description}->{P3};
	my $resultsDescP4 = $infoYaml->{results_info}->{results_description}->{P4};
	my $expOrganism = $experimentYaml->{experiment}->{organism};
	my $chipOrg = "chip_".$expOrganism;
	my $chipName = $infoYaml->{illumina_info}->{$chipOrg}->{name};
	my $chipVersion = $infoYaml->{illumina_info}->{$chipOrg}->{version};
	my $chipAnnotation =  $infoYaml->{illumina_info}->{$chipOrg}->{annotation};
	my $chipNameVersionText = $chipName." version ".$chipVersion;
	my $remoatAnnotation = $infoYaml->{results_info}->{annotation}->{other}->{remoat};
	my $bioconductorOrganism = $expOrganism."_anno";
	my $bioconductorAnnoText = $infoYaml->{results_info}->{annotation}->{bioconductor}->{$bioconductorOrganism};
	my $genomeStudioVersion = $infoYaml->{analysis_info}->{software_versions}->{genomestudio};
	my $rVersion = $infoYaml->{analysis_info}->{software_versions}->{r};
	my $bioconductorVersion = $infoYaml->{analysis_info}->{software_versions}->{bioconductor};
	my $migbeadarrayVersion = $infoYaml->{analysis_info}->{software_versions}->{migbeadarray};
	my $visibilityList = $expIName."\t".$expIUser."\n";
	## make text replacements
	$markup_file_text =~ s/\*expName\*/$expName/g;
	$markup_file_text =~ s/\*expDate\*/$expDate/g;
	$markup_file_text =~ s/\*expOverview\*/$expOverview/g;
	$markup_file_text =~ s/\*expIUser\*/$expIUser/g;
	$markup_file_text =~ s/\*expSampleSetName\*/$expSampleSetName/g;
	$markup_file_text =~ s/\*expDesign\*/$expDesign/g;
	$markup_file_text =~ s/\*analysisDescription\*/$analysisDescription/g;
	$markup_file_text =~ s/\*datePurge\*/$datePurge/g;
	$markup_file_text =~ s/\*rawQCfileName\*/$rawQCfileName/g;
	$markup_file_text =~ s/\*normQCfileName\*/$normQCfileName/g;
	$markup_file_text =~ s/\*qcDescription\*/$qcDescription/g;
	$markup_file_text =~ s/\*expComparisons\*/$expComparisons/g;
	$markup_file_text =~ s/\*resultsDescP1\*/$resultsDescP1/g;
	$markup_file_text =~ s/\*resultsDescP2\*/$resultsDescP2/g;
	$markup_file_text =~ s/\*resultsDescP3\*/$resultsDescP3/g;
	$markup_file_text =~ s/\*resultsDescP4\*/$resultsDescP4/g;
	$markup_file_text =~ s/\*expLName\*/$expLName/g;
	$markup_file_text =~ s/\*expLMail\*/$expLMail/g;
	$markup_file_text =~ s/\*expAName\*/$expAName/g;
	$markup_file_text =~ s/\*expAMail\*/$expAMail/g;
	$markup_file_text =~ s/\*chipNameVersionText\*/$chipNameVersionText/g;
	$markup_file_text =~ s/\*chipAnnotation\*/$chipAnnotation/g;
	$markup_file_text =~ s/\*bioconductorAnnoText\*/$bioconductorAnnoText/g;
	$markup_file_text =~ s/\*remoatAnnotation\*/$remoatAnnotation/g;
	$markup_file_text =~ s/\*genomeStudioVersion\*/$genomeStudioVersion/g;
	$markup_file_text =~ s/\*rVersion\*/$rVersion/g;
	$markup_file_text =~ s/\*bioconductorVersion\*/$bioconductorVersion/g;
	$markup_file_text =~ s/\*migbeadarrayVersion\*/$migbeadarrayVersion/g;
	$markup_file_text =~ s/\*visibilityList\*/$visibilityList/g;
	## print the file
	print FH_MARKUP $markup_file_text;
	close(FH_MARKUP);
}

sub rCodeFormatter($$$){
	my ($experimentYaml, $r_scriptYaml, $codeChunkId) = @_;

	## obtain piece of code
	my $codeChunk = $r_scriptYaml->{r_script}->{$codeChunkId};

	if($codeChunkId eq 'hdr_libraries_functions'){
		## obtain organism
		my $expOrganism = ucfirst($experimentYaml->{experiment}->{organism});	
		## format code
		$codeChunk =~ s/<organism>.*<\/organism>/$expOrganism/g;
	}
	if($codeChunkId eq 'stmt_function_qcreport'){
		## nothing to be done for this piece of code
		## (it applies only to the rscript but not 
		## the sweave document.
	}	
	if($codeChunkId eq 'stmt_input'){
		## experiment name
		my $expExperiment = $experimentYaml->{experiment}->{name};	
		## format code for input
		$codeChunk =~ s/<file_stem>.*<\/file_stem>/$expExperiment/g;
	}
	if($codeChunkId eq 'stmt_qc'){
		## deal with outliers, obtain list from experiment yaml
		## enclose outliers between ""
		my @outliers = map("\"".$_."\"",@{$experimentYaml->{analysis}->{outliers}});
		my $expOutliers = join(",",@outliers);
		## format code for qc
		$codeChunk =~ s/<outliers>.*<\/outliers>/$expOutliers/g;
	}
	if(($codeChunkId eq 'stmt_qc_report_rscript') || ($codeChunkId eq 'stmt_qc_report_sweave')){
		## obtain sample names from experiment yaml
		## these are normally contained in the column sampleID of the targets file
		## but a different column or combination of columns could be used
		my @expSampleNames = map("targets\$".$_, @{$experimentYaml->{analysis}->{sample_names}});
		my $expQCReports = join(",",@expSampleNames);
		## format code
		$codeChunk =~ s/<sample_names>.*<\/sample_names>/$expQCReports/g;
	}
	if($codeChunkId eq 'cmnt_analysis'){
		## clean up code string
		$codeChunk = "";
		## temporary code string
		my $codeChunkTemp = "";
		## obtain differential expression analyses from experiment's yaml
		my %expAnalyses = %{$experimentYaml->{analysis}};
		my @analysis = grep(/analysis/, keys %expAnalyses);
		my @factors;
		my @contrasts;
		my $analysisName = "";
		my $expFactors = "";
		my $expContrasts = "";
		my $analysisSubdir = "";

		## the next loop reads in the experiment's yaml file, extracting each of
		## the DE analyses (keys 'analysis[X]:') defined in the key 'analysis:' 
		foreach my $analysis (@analysis){
			## obtain piece of code with comment describing the current analysis
			$codeChunkTemp = $r_scriptYaml->{r_script}->{cmnt_analysis};
			## format code
			$analysisName = $experimentYaml->{analysis}->{$analysis}->{name};
			chomp($analysisName);
			$codeChunkTemp =~ s/<name>.*<\/name>/$analysisName/g;
			## add description comment
		    $codeChunk = $codeChunk.$codeChunkTemp."\n\n";
		    
			## obtain piece of code for the experimental factors
			## but first define if they are single or multiple
		    @factors = map("targets\$".$_, @{$experimentYaml->{analysis}->{$analysis}->{factors}});
		    if(scalar @factors == 1){
		        $codeChunkTemp = $r_scriptYaml->{r_script}->{stmt_expFactorsSingle};
		    }elsif(scalar @factors > 1){
		        $codeChunkTemp = $r_scriptYaml->{r_script}->{stmt_expFactorsMulti};
		    }
		    $expFactors = join(",",@factors);
		    ## format code and add experimental factors 
		    $codeChunkTemp =~ s/<factors>.*<\/factors>/$expFactors/g;
			$codeChunk = $codeChunk.$codeChunkTemp."\n\n";
			
			## obtain the piece of code for the experimental design
			## this includes the contrasts for this analysis
			$codeChunkTemp = $r_scriptYaml->{r_script}->{stmt_expDesign};
			## define contrasts
			@contrasts = map("\"".$_."\"", @{$experimentYaml->{analysis}->{$analysis}->{contrasts}});
			$expContrasts = join(",", @contrasts);
			## format code and add experimental design
		    $codeChunkTemp =~ s/<contrasts>.*<\/contrasts>/$expContrasts/g;
		    $codeChunk = $codeChunk.$codeChunkTemp."\n\n";
		    
		    ## the output of each analysis is stored in its own subdirectory
		    ## obtain the code that creates the subdirectory of this analysis
		    $codeChunkTemp = $r_scriptYaml->{r_script}->{stmt_outputDir};
		    ## if only one analysis the default directory is 'output'
		    ## otherwise assign a new one{ named as the key of this analysis
		    if (scalar @analysis > 1){
		        $analysisSubdir = $analysis."/";
		    }
		    ## format code and add
		    $codeChunkTemp =~ s/<analysis_subdir>.*<\/analysis_subdir>/$analysisSubdir/g;
		    $codeChunk = $codeChunk.$codeChunkTemp."\n\n";
		    
		    ## obtain piece of code for top tables and add it
		    $codeChunkTemp = $r_scriptYaml->{r_script}->{stmt_topTable};
		    $codeChunk = $codeChunk.$codeChunkTemp."\n\n";
		}	
		## obtain piece of code for end of run and add it
		$codeChunkTemp = $r_scriptYaml->{r_script}->{stmt_finish_run};
		$codeChunk = $codeChunk.$codeChunkTemp;
	}

	return($codeChunk."\n");
}

sub get_timestamp {
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
   my @Month = qw(January February March April May June July August September October November December);
   $year=$year+1900;
   return $Month[$mon]." ".$year;
}

sub formatTargetsOutput($$$$$$){
	## get parameters
	my ($refTargetsData, $fileName, $deleteFileNameCol,$colsep,$offsetchar,$offsetnum) = @_;
	
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
	my $offset = $offsetchar x $offsetnum;
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
	    $targetsText = $targetsText."\n".$offset.join($colsep,@cols);
	}
	$targetsText = " ".$targetsText;
    return ($targetsText);
}

sub rScriptOld($$$){
	my ($experimentYaml, $hRefTargets, $r_scriptYaml) = @_;
	## file name
	my $expExperiment = $experimentYaml->{experiment}->{name};
	## organism
	my $expOrganism = ucfirst($experimentYaml->{experiment}->{organism});
	
	## create R script file:
	my $r_script_file = $expExperiment."/".$expExperiment.".R";
	open FH_RSCRIPT, ">$r_script_file" or die "file $r_script_file could not be created\n";

	## start writing R script by mixing both 
	## experiment and r_script yaml files
	
	## obtain piece of code for libraries and functions
	my $codeChunk = $r_scriptYaml->{r_script}->{hdr_libraries_functions};
	## get no. of samples and decide point size and page width
	#my $countSamples = scalar @{$hRefTargets->{name}};
	#my $pointSize = 1;
	#my $pageWidth = 20;
	#if($countSamples<=15){
	#	($pointSize,$pageWidth) = (12,7);	
	#}elsif (($countSamples>15)&&($countSamples<=30)){
	#	($pointSize,$pageWidth) = (10,9);
	#}elsif (($countSamples>30)&&($countSamples<=45)){
	#	($pointSize,$pageWidth) = (8,11);
	#}elsif (($countSamples>45)&&($countSamples<=60)){
	#	($pointSize,$pageWidth) = (6,13);
	#}elsif ($countSamples>60){
	#	($pointSize,$pageWidth) = (4,15);
	#}
	## format code
	$codeChunk =~ s/<organism>.*<\/organism>/$expOrganism/g;
	#$codeChunk =~ s/<pointsize>.*<\/pointsize>/$pointSize/g;
	#$codeChunk =~ s/<pagewidth>.*<\/pagewidth>/$pageWidth/g;
	## print libraries and functions
	print FH_RSCRIPT $codeChunk."\n\n";
	
	## obtain piece of code for QC reports (they apply only to the)
	## rscript but not the sweave document. And print it.
	$codeChunk = $r_scriptYaml->{r_script}->{stmt_function_qcreport};
	print FH_RSCRIPT $codeChunk."\n\n";
	
	## obtain piece of code for input
	$codeChunk = $r_scriptYaml->{r_script}->{stmt_input};
	## format code
	$codeChunk =~ s/<file_stem>.*<\/file_stem>/$expExperiment/g;	
	## print input
	print FH_RSCRIPT $codeChunk."\n\n";
	
	## obtain code for qc
	$codeChunk = $r_scriptYaml->{r_script}->{stmt_qc};
	## deal with outliers, obtain list from experiment yaml
	my @outliers = map("\"".$_."\"",@{$experimentYaml->{analysis}->{outliers}});
	my $expOutliers = join(",",@outliers);
	my $scriptRemOutlier = "";
	if(scalar @outliers > 0){
	    $scriptRemOutlier = ".remoutlier";
	}
	$codeChunk =~ s/<outliers>.*<\/outliers>/$expOutliers/g;
	$codeChunk =~ s/<remoutlier>.*<\/remoutlier>/$scriptRemOutlier/g;	
	## print qc
	print FH_RSCRIPT $codeChunk."\n\n";

	## obtain code for qc reports
	$codeChunk = $r_scriptYaml->{r_script}->{stmt_qc_report_rscript};
	## obtain sample names from experiment yaml
	## these are normally contained in the column sampleID of the targets file 
	## but a different column or combination of columns could be used
	my @expSampleNames = map("targets\$".$_, @{$experimentYaml->{analysis}->{sample_names}});
	my $expQCReports = join(",",@expSampleNames);
	## format code
	$codeChunk =~ s/<sample_names>.*<\/sample_names>/$expQCReports/g;
	## print qc reports
	print FH_RSCRIPT $codeChunk."\n\n";
	
	## obtain differential expression analyses from experiment's yaml
	my %expAnalyses = %{$experimentYaml->{analysis}};
	my @analysis = grep(/analysis/, keys %expAnalyses);
	my @factors;
	my @contrasts;
	my $analysisName = "";
	my $expFactors = "";
	my $expContrasts = "";
	my $analysisSubdir = "";
	my $makeSubdirs = 0;
	$makeSubdirs = 1 if (scalar @analysis>1);

	## the next loop reads in the experiment's yaml file, extracting each of
	## the DE analyses (keys 'analysis[X]:') defined in the key 'analysis:' 
	foreach my $analysis (@analysis){
		## obtain piece of code with comment describing the current analysis
		$codeChunk = $r_scriptYaml->{r_script}->{cmnt_analysis};
		## format code
		$analysisName = $experimentYaml->{analysis}->{$analysis}->{name};
		chomp($analysisName); 
		$codeChunk =~ s/<name>.*<\/name>/$analysisName/g;
		## print description comment
	    print FH_RSCRIPT $codeChunk."\n\n";

		## obtain piece of code for the experimental factors
		## but first define if they are single or multiple
	    @factors = map("targets\$".$_, @{$experimentYaml->{analysis}->{$analysis}->{factors}});
	    if(scalar @factors == 1){
	        $codeChunk = $r_scriptYaml->{r_script}->{stmt_expFactorsSingle};
	    }elsif(scalar @factors > 1){
	        $codeChunk = $r_scriptYaml->{r_script}->{stmt_expFactorsMulti};
	    }
	    $expFactors = join(",",@factors);
	    ## format code
	    $codeChunk =~ s/<factors>.*<\/factors>/$expFactors/g;
	    ## print experimental factors
		print FH_RSCRIPT $codeChunk."\n\n";
		
		## obtain the piece of code for the experimental design
		## this includes the contrasts for this analysis
		$codeChunk = $r_scriptYaml->{r_script}->{stmt_expDesign};
		## define contrasts
		@contrasts = map("\"".$_."\"", @{$experimentYaml->{analysis}->{$analysis}->{contrasts}});
		$expContrasts = join(",", @contrasts);
		## format code
	    $codeChunk =~ s/<contrasts>.*<\/contrasts>/$expContrasts/g;
	    ## print experimental design
	    print FH_RSCRIPT $codeChunk."\n\n";
	    
	    ## the output of each analysis is stored in its own subdirectory
	    ## obtain the code that creates the subdirectory of this analysis
	    $codeChunk = $r_scriptYaml->{r_script}->{stmt_outputDir};
	    ## if only one analysis the default directory is 'output'
	    ## otherwise assign a new one named as the key of this analysis
	    if($makeSubdirs){
	        $analysisSubdir = $analysis."/";
	    }
	    ## format code
	    $codeChunk =~ s/<analysis_subdir>.*<\/analysis_subdir>/$analysisSubdir/g;
	    ##print code
	    print FH_RSCRIPT $codeChunk."\n\n";
	    
	    ## obtain piece of code for top tables and print it
	    print FH_RSCRIPT "$r_scriptYaml->{r_script}->{stmt_topTable}\n\n";
	}
    
    ## obtain piece of code for end of run and print it
	print FH_RSCRIPT "$r_scriptYaml->{r_script}->{stmt_finish_run}\n\n";
	## close file
	close(FH_RSCRIPT);	
}

1;