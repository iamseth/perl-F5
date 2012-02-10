#!perl -T

use Test::More tests => 1;
use lib './lib';

BEGIN {
    use_ok( 'F5' ) || print "Bail out!
";
}

diag( "Testing F5 $F5::VERSION, Perl $], $^X" );
