use strict;
use warnings;
use utf8;
use Test::More;
use File::Zglob;
use Data::Dumper;

$File::Zglob::DEBUG = $ENV{DEBUG} ? 1 : 0;

is_deeply2('*/*.t', [qw(t/00_compile.t  t/01_glob_expand_braces.t  t/02_glob_prepare_pattern.t  t/03_zglob.t  xt/01_podspell.t  xt/02_perlcritic.t  xt/03_pod.t  xt/04_minimum_version.t)]);
is_deeply2('lib/File/Zglob.pm', ['lib/File/Zglob.pm']);
is_deeply2('lib/*/Zglob.pm', ['lib/File/Zglob.pm']);
is_deeply2('lib/File/*.pm', ['lib/File/Zglob.pm']);
is_deeply2('l*/*/*.pm', ['lib/File/Zglob.pm']);
is_deeply2('t/dat/very/deep/*', ['t/dat/very/deep/normalfile'], "don't match dotfile");
is_deeply2('t/dat/very/deep/.*', ['t/dat/very/deep/.dotfile'], "dotfile");
if (-f '/etc/passwd') {
    is_deeply2('/etc/passwd', ['/etc/passwd']);
}

done_testing;

sub is_deeply2 {
    local $Data::Dumper::Purity = 1;
    local $Data::Dumper::Sortkeys = 1;
    local $Data::Dumper::Indent = 0;

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my ($pattern, $expected, $reason) = @_;
    is(Dumper([sort { $a cmp $b } zglob($pattern)]), Dumper([sort @$expected]), $reason || $pattern) or do {
        die "ABORT" if $File::Zglob::DEBUG;
    };
}
