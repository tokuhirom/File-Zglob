package File::Zglob;
use strict;
use warnings FATAL => 'recursion';
use 5.008008;
our $VERSION = '0.05';
use base qw(Exporter);

our @EXPORT = qw(zglob);

use File::Basename;

sub subname { $_[1] }
# use Sub::Name qw(subname);

our $SEPCHAR = $^O eq 'Win32' ? '\\' : '/';
our $NOCASE = $^O =~ /^(?:MSWin32|VMS|os2|dos|riscos|MacOS|darwin)$/ ? 1 : 0;
our $DIRFLAG = \"DIR?";
our $DEEPFLAG = \"**";
our $DEBUG = 0;
our $STRICT_LEADING_DOT    = 1;
our $STRICT_WILDCARD_SLASH = 1;

sub zglob {
    my ($pattern) = @_;
    $pattern =~ s!^(\~[^$SEPCHAR]*)![glob($1)]->[0]!e; # support ~tokuhirom/
    return zglob_fold($pattern, \&cons, []);
}

sub dbg(@) {
    return unless $DEBUG;
    my ($pkg, $filename, $line, $sub) = caller(1);
    my $i = 0;
    while (caller($i++)) { 1 }
    my $msg;
    $msg .= ('-' x ($i-5));
    $msg .= " [$sub] ";
    for (@_) {
        $msg .= ' ';
        if (not defined $_) {
            $msg .= '<<undef>>';
        } elsif (ref $_) {
            local $Data::Dumper::Terse = 1;
            local $Data::Dumper::Indent = 0;
            $msg .= Data::Dumper::Dumper($_);
        } else {
            $msg .= $_;
        }
    }
    $msg .= " at $filename line $line\n";
    print($msg);
}

sub zglob_fold {
    my ($patterns, $proc, $seed) = @_;
    my @ret;
    for my $pattern (glob_expand_braces($patterns)) {
        push @ret, @{glob_fold_1($pattern, $proc, $seed)};
    }
    return @ret;
}

sub cons { [$_[0], @{$_[1]}] }

sub glob_fold_1 {
    my ($pattern, $proc, $seed) = @_;
    #dbg("FOLDING: $pattern");
    my ($rec, $recstar);
    $recstar = subname('recstar', sub {
        my ($node, $matcher, $seed) = @_;
        #dbg("recstar: ", $node, $matcher, $seed);
        my $dat = glob_fs_fold(\&cons, [], $node, qr{^[^.].*$}, 1);
        my $foo = $rec->($node, $matcher, $seed);
        #dbg("recstar:: dat: ", $dat, " foo: ", $foo);
        for my $thing (@$dat) {
            $foo = $recstar->($thing, $matcher, $foo);
        }
        return $foo;
    });
    $rec = subname('rec' => sub {
        my ($node, $matcher, $seed) = @_;
        #dbg($node, $matcher, $seed);
        my ($current, @rest) = @{$matcher};
        if (!defined $current) {
            #dbg("FINISHED");
            return $seed;
        } elsif (ref($current) eq 'SCALAR' && $current == $DEEPFLAG) {
            #dbg("** mode");
            return $recstar->($node, \@rest, $seed);
        } elsif (@rest == 0) {
            #dbg("file name");
            # (folder proc seed node (car matcher) #f)
            return glob_fs_fold($proc, $seed, $node, $current, 0);
        } else {
            #dbg "NORMAL MATCH";
            return glob_fs_fold(sub {
                # my ($node, $seed) = @_;
                #dbg("NEXT: ", $node, \@rest);
                return $rec->($_[0], \@rest, $_[1]);
            }, $seed, $node, $current, 1);
        }
    });
    my ($node, $matcher) = glob_prepare_pattern($pattern);
    #dbg("pattern: ", $node, $matcher);
    return $rec->($node, $matcher, $seed);
}

# /^home$/ のような固定の文字列の場合に高速化をはかるための最適化予定地なので、とりあえず undef をかえしておいても問題がない
sub fixed_regexp_p {
    return undef;
    die "TBI"
}

# returns arrayref of seeds.
sub glob_fs_fold {
    my ($proc, $seed, $node, $regexp, $non_leaf_p) = @_;
    my $prefix = do {
        if (ref $node eq 'SCALAR') {
            if ($$node eq 1) { #t
                $SEPCHAR
            } elsif ($$node eq '0') { #f
                '';
            } else {
                die "FATAL";
            }
        } else {
            $node . '/';
        }
    };
    #dbg("prefix: $prefix");
    #dbg("regxp: ", $regexp);
    if (ref $regexp eq 'SCALAR' && $regexp == $DIRFLAG) {
        $proc->($prefix, $seed);
    } elsif (my $string_portion = fixed_regexp_p($regexp)) { # /^path$/
        my $full = $prefix . $string_portion;
        if (-e $full && (!$non_leaf_p || -d $full)) {
            $proc->($full, $seed);
        } else {
            $proc;
        }
    } else { # normal regexp
        #dbg("normal regexp");
        my $dir = do {
            if (ref($node) eq 'SCALAR' && $$node eq 1) {
                $SEPCHAR
            } elsif (ref($node) eq 'SCALAR' && $$node eq 0) {
                '.';
            } else {
                $node;
            }
        };
        #dbg("dir: $dir");
        opendir my $dirh, $dir or do {
            #dbg("cannot open dir: $dir: $!");
            return $seed;
        };
        while (defined(my $child = readdir($dirh))) {
            next if $child eq '.' or $child eq '..';
            my $full;
            #dbg("non-leaf: ", $non_leaf_p);
            if (($child =~ $regexp) && ($full = $prefix . $child) && (!$non_leaf_p || -d $full)) {
                #dbg("matched: ", $regexp, $child, $full);
                $seed = $proc->($full, $seed);
            } else {
                #dbg("Don't match: $child");
            }
        }
        return $seed;
    }
}

sub glob_prepare_pattern {
    my ($pattern) = @_;
    my @path = split $SEPCHAR, $pattern;

    my $is_absolute = $path[0] eq '' ? 1 : 0;
    if ($is_absolute) {
        shift @path;
    }

    @path = map {
        if ($_ eq '**') {
            $DEEPFLAG
        } elsif ($_ eq '') {
            $DIRFLAG
        } else {
            glob_to_regex($_) # TODO: replace with original implementation?
        }
    } @path;

    return ( \$is_absolute, \@path );
}

# TODO: better error detection?
# TODO: nest support?
sub glob_expand_braces {
    my ($pattern, @more) = @_;
    if (my ($prefix, $body, $suffix) = ($pattern =~ /^(.*)\{([^}]+)\}(.*)$/)) {
        return (
            ( map { glob_expand_braces("$prefix$_$suffix") } split /,/, $body ),
            @more
        );
    } else {
        return ($pattern, @more);
    }
}

sub glob_to_regex {
    my $glob = shift;
    my $regex = glob_to_regex_string($glob);
    return $NOCASE ? qr/^$regex$/i : qr/^$regex$/;
}

sub glob_to_regex_string {
    my $glob = shift;
    my ($regex, $in_curlies, $escaping);
    local $_;
    my $first_byte = 1;
    for ($glob =~ m/(.)/gs) {
        if ($first_byte) {
            if ($STRICT_LEADING_DOT) {
                $regex .= '(?=[^\.])' unless $_ eq '.';
            }
            $first_byte = 0;
        }
        if ($_ eq '/') {
            $first_byte = 1;
        }
        if ($_ eq '.' || $_ eq '(' || $_ eq ')' || $_ eq '|' ||
            $_ eq '+' || $_ eq '^' || $_ eq '$' || $_ eq '@' || $_ eq '%' ) {
            $regex .= "\\$_";
        }
        elsif ($_ eq '*') {
            $regex .= $escaping ? "\\*" :
              $STRICT_WILDCARD_SLASH ? "[^/]*" : ".*";
        }
        elsif ($_ eq '?') {
            $regex .= $escaping ? "\\?" :
              $STRICT_WILDCARD_SLASH ? "[^/]" : ".";
        }
        elsif ($_ eq '{') {
            $regex .= $escaping ? "\\{" : "(";
            ++$in_curlies unless $escaping;
        }
        elsif ($_ eq '}' && $in_curlies) {
            $regex .= $escaping ? "}" : ")";
            --$in_curlies unless $escaping;
        }
        elsif ($_ eq ',' && $in_curlies) {
            $regex .= $escaping ? "," : "|";
        }
        elsif ($_ eq "\\") {
            if ($escaping) {
                $regex .= "\\\\";
                $escaping = 0;
            }
            else {
                $escaping = 1;
            }
            next;
        }
        else {
            $regex .= $_;
            $escaping = 0;
        }
        $escaping = 0;
    }

    return $regex;
}

1;
__END__

=encoding utf8

=head1 NAME

File::Zglob - Extended globs.

=head1 SYNOPSIS

    use File::Zglob;

    my @files = zglob('**/*.{pm,pl}');

=head1 DESCRIPTION

B<WARNINGS: THIS IS ALPHA VERSION. API MAY CHANGE WITHOUT NOTICE>

Provides a traditional Unix glob(3) functionality; returns a list of pathnames that matches the given pattern.

File::Zglob provides extended glob. It supports C<< **/*.pm >> form.

=head1 FUNCTIONS

=over 4

=item zglob($pattern) # => list of matched files

    my @files = zglob('**/*.[ch]');

Unlike shell’s glob, if there’s no matching pathnames, () is returned.

=back

=head1 Special chars

A glob pattern also consists of components and separator characters. In a component, following characters/syntax have special meanings.

=over 4

=item C<< * >>

When it appears at the beginning of a component, it matches zero or more characters except a period (.). And it won’t match if the component of the input string begins with a period.

Otherwise, it matches zero or more sequence of any characters.

=item C<< ** >>

If a component is just **, it matches zero or more number of components that match *. For example, src/**/*.h matches all of the following patterns.

    src/*.h
    src/*/*.h
    src/*/*/*.h
    src/*/*/*/*.h
    ...

=item C<< ? >>

When it appears at the beginning of a component, it matches a character except a period (.). Otherwise, it matches any single character.

=item C<< [chars] >>

Specifies a character set. Matches any one of the set. The syntax of chars is the same as perl’s character set syntax. 

=item C<< {pm,pl} >>

There is alternation.

"example.{foo,bar,baz}" matches "example.foo", "example.bar", and "example.baz"

=back

=head1 zglob and deep recursion

C<< **/* >> form makes deep recursion by soft link. zglob throw exception if it's deep recursion.

=head1 PORTABILITY

I don't tested this module on Win32 environment. If you want to write a patch, please send me a github pull-req.

=head1 LIMITATIONS

=over 4

=item File order is not compatible with shells.

=back

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom AAJKLFJEF GMAIL COME<gt>

=head1 THANKS TO

Most code was translated from gauche's fileutil.scm.

glob_to_regex function is taken from L<Text::Glob>.

=head1 SEE ALSO

L<File::DosGlob>, L<Text::Glob>, gauche's fileutil.scm

=head1 LICENSE

Copyright (C) Tokuhiro Matsuno

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
