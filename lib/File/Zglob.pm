package File::Zglob;
use strict;
use warnings 'all', FATAL => 'recursion';
use 5.008008;
our $VERSION = '0.08';
use base qw(Exporter);

our @EXPORT = qw(zglob);

use File::Basename;

our $SEPCHAR    = '/';
our $NOCASE = $^O =~ /^(?:MSWin32|VMS|os2|dos|riscos|MacOS|darwin)$/ ? 1 : 0;
our $DIRFLAG = \"DIR?";
our $DEEPFLAG = \"**";
our $DEBUG = 0;
our $STRICT_LEADING_DOT    = 1;
our $STRICT_WILDCARD_SLASH = 1;

sub zglob {
    my ($pattern) = @_;
    #dbg("FOLDING: $pattern");
    # support ~tokuhirom/
    if ($^O eq 'MSWin32') {
        require Win32;
        $pattern =~ s!^(\~[^$SEPCHAR]*)!Win32::GetLongPathName([glob($1)]->[0])!e;
    } else {
        $pattern =~ s!^(\~[^$SEPCHAR]*)![glob($1)]->[0]!e;
    }
    my ($node, $matcher) = glob_prepare_pattern($pattern);
    #dbg("pattern: ", $node, $matcher);
    return _rec($node, $matcher, []);
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

sub _recstar {
    my ($node, $matcher) = @_;
    #dbg("recstar: ", $node, $matcher, $seed);
    return (
        _rec( $node, $matcher ),
        (
            map { _recstar( $_, $matcher ) }
              glob_fs_fold( $node, qr{^[^.].*$}, 1 )
        )
    );
}

sub _rec {
    my ($node, $matcher) = @_;
    my ($current, @rest) = @{$matcher};
    if (!defined $current) {
        #dbg("FINISHED");
        return ();
    } elsif (ref($current) eq 'SCALAR' && $current == $DEEPFLAG) {
        #dbg("** mode");
        return _recstar($node, \@rest);
    } elsif (@rest == 0) {
        #dbg("file name");
        # (folder proc seed node (car matcher) #f)
        return glob_fs_fold($node, $current, 0);
    } else {
        return glob_fs_fold($node, $current, 1, \@rest);
    }
}


# /^home$/ のような固定の文字列の場合に高速化をはかるための最適化予定地なので、とりあえず undef をかえしておいても問題がない
sub fixed_regexp_p {
    return undef;
    die "TBI"
}

# returns arrayref of seeds.
sub glob_fs_fold {
    my ($node, $regexp, $non_leaf_p, $rest) = @_;
    my $prefix = do {
        if (ref $node eq 'SCALAR') {
            if ($$node eq 1) { #t
                $SEPCHAR
            } elsif ($$node eq '0') { #f
                '';
            } else {
                die "FATAL";
            }
        } elsif ($node !~ m{/$}) {
            $node . '/';
        } else {
            $node;
        }
    };
    #dbg("prefix: $prefix");
    #dbg("regxp: ", $regexp);
    if ($^O eq 'MSWin32' && ref $regexp eq 'SCALAR' && $$regexp =~ /^[a-zA-Z]\:$/) {
        return _rec($$regexp . '/', $rest);
    }
    if (ref $regexp eq 'SCALAR' && $regexp == $DIRFLAG) {
        if ($rest) {
            return _rec($prefix, $rest);
        } else {
            return ($prefix);
        }
#   } elsif (my $string_portion = fixed_regexp_p($regexp)) { # /^path$/
#       die "TBI";
#       my $full = $prefix . $string_portion;
#       if (-e $full && (!$non_leaf_p || -d $full)) {
#           $proc->($full, $seed);
#       } else {
#           $proc;
#       }
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
            return ();
        };
        my @ret;
        while (defined(my $child = readdir($dirh))) {
            next if $child eq '.' or $child eq '..';
            my $full;
            #dbg("non-leaf: ", $non_leaf_p);
            if (($child =~ $regexp) && ($full = $prefix . $child) && (!$non_leaf_p || -d $full)) {
                #dbg("matched: ", $regexp, $child, $full);
                if ($rest) {
                    push @ret, _rec($full, $rest);
                } else {
                    push @ret, $full;
                }
          # } else {
                #dbg("Don't match: $child");
            }
        }
        return @ret;
    }
}

sub glob_prepare_pattern {
    my ($pattern) = @_;
    my @path = split $SEPCHAR, $pattern;

    my $is_absolute = $path[0] eq '' ? 1 : 0;
    if ($is_absolute) {
        shift @path;
    }
    if ($^O eq 'MSWin32' && $path[0] =~ /^[a-zA-Z]\:$/) {
        $is_absolute = 1;
    }

    @path = map {
        if ($_ eq '**') {
            $DEEPFLAG
        } elsif ($_ eq '') {
            $DIRFLAG
        } elsif ($_ eq '.') {
            ()
        } elsif ($^O eq 'MSWin32' && $_ =~ '^[a-zA-Z]\:$') {
            \$_
        } else {
            glob_to_regex($_) # TODO: replace with original implementation?
        }
    } @path;

    return ( \$is_absolute, \@path );
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

=over 4

=item Win32

Zglob supports Win32. zglob() only uses '/' as a path separator. Since zglob() accepts non-utf8 strings. CP932 contains '\' character as a second byte of multibyte chars.

=back

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
