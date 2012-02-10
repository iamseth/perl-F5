use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'F5',
    AUTHOR       => q{Seth Miller <seth@migrantgeek>},
    VERSION_FROM => 'lib/F5.pm',
    ( $ExtUtils::MakeMaker::VERSION >= 6.3002
        ? ( 'LICENSE' => 'perl' )
        : () ),
    PREREQ_PM => {
        'Test::More' => 0,
        'Carp'       => 0,
        'Exporter'   => 0,
        'SOAP::Lite' => 0
    },
    dist => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', }
);
