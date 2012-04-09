use strict;
use warnings;
use utf8;
use Test::More;
use File::Zglob qw(zglob);
use Fatal qw(chdir);
use File::Basename qw(dirname basename);

local $File::Zglob::NOCASE = 0; # case sensitive to pass tests.

my $this_dir   = dirname(__FILE__);
my $parent_dir = dirname($this_dir);

chdir $this_dir;

my @abs = map { basename($_) } zglob($parent_dir . "/lib/**/*.pm");
is_deeply \@abs, [qw(Zglob.pm)];

is_deeply [map { basename($_) } zglob("$this_dir/../lib/**/*.pm")], \@abs;
is_deeply [map { basename($_) } zglob(          "../lib/**/*.pm")], \@abs;


done_testing;

