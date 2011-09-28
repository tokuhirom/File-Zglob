use strict;
use warnings;
use utf8;
use Test::More;

use File::Zglob;

*g = *File::Zglob::glob_expand_braces;

subtest 'normal' => sub {
    is(join("--", g("*.{c,h}")), "*.c--*.h");
    is(join("--", sort { $a cmp $b } g("{x,y}.*.{c,h}")), "x.*.c--x.*.h--y.*.c--y.*.h");
};

done_testing;

