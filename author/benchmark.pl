#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use 5.010000;

use Benchmark qw(:all);
use lib 'lib';
use File::Zglob;
use File::Glob qw(bsd_glob);

my $t = timethese(50_000, {
    glob => sub {
        glob('*/*.t')
    },
    zglob => sub {
        zglob('*/*.t')
    },
    bsd_glob => sub {
        bsd_glob('*/*.t')
    },
});
cmpthese($t);

