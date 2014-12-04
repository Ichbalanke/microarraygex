use 5.006;
use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;
use File::ShareDir::Install;

install_share dist => 'share';

WriteMakefile(
    NAME               => 'MicroarrayGEX',
    AUTHOR             => 'Ruben E. Bautista (rb11@sanger.ac.uk)',
    VERSION_FROM       => 'lib/MicroarrayGEX.pm',
    ABSTRACT           => 'Create an Illumina beadarray data analysis project',
    EXE_FILES          => ['bin/imgex_analysis.pl'],
    MIN_PERL_VERSION   => 5.006,
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    BUILD_REQUIRES => {
        'Test::More' => 0,
    },
    PREREQ_PM    => {
    	'Test::Simple' => 0.44,
    	'YAML::XS'     => 0,
    	'File::Share'  => 0
    },
);

package MY;
use File::ShareDir::Install qw(postamble);