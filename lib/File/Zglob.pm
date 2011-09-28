package File::Zglob;
use strict;
use warnings;
use 5.008008;
our $VERSION = '0.01';
use parent qw(Exporter);

our @EXPORT = qw(zglob);

use autodie;
use File::Find qw(find);
use Text::Glob qw(glob_to_regex);
use File::Basename;
use Smart::Comments;

our $SEPCHAR = $^O eq 'Win32' ? '\\' : '/';
our $DIRFLAG = \"DIR?";
our $DEEPFLAG = \"**";
our $DEBUG = 0;

sub zglob {
    my ($pattern, $folder) = @_;
    return glob_fold($pattern, sub {
        my ($node, $seed) = @_;
        [$node, @$seed];
    }, [], $folder);
}

# see lib/gauche/fileutil.scm

use Carp;
sub dbg(@) {
    return unless $DEBUG;
    my $i = 0;
    while (caller($i++)) { 1 }
    my ($pkg, $filename, $line, $sub) = caller(0);
    my $msg;
    $msg .= ('-' x $i);
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
    Carp::carp($msg);
}

sub glob_fold {
    my ($patterns, $proc, $seed, $folder) = @_;
    my @ret;
    for my $pattern (glob_expand_braces($patterns)) {
        push @ret, @{glob_fold_1($pattern, $proc, $seed, $folder)};
    }
    return @ret;
}

sub cdr {
    my $x = shift;
    my ($first, @more) = @$x;
    return \@more;
}
# (define (glob-fold patterns proc seed . opts)
#   (fold (cut glob-fold-1 <> proc <> opts) seed
#           (fold glob-expand-braces '()
#               (if (list? patterns) patterns (list patterns)))))

sub glob_fold_1 {
    my ($pattern, $proc, $seed, $folder) = @_;
    dbg("FOLDING: $pattern");
    $folder ||= make_glob_fs_fold();
    my $recstar = sub {
        my ($node, $matcher, $seed) = @_;
#       my $dat = $folder->(sub { [$_[0], @{$_[1]}] }, [], $node, qr{^[^.].*$}, \1);
#       $rec->($node, $matcher, $seed);
        die "TBI";
#   (define (rec* node matcher seed)
#     (fold (cut rec* <> matcher <>)
#           (rec node matcher seed)
#           (folder cons '() node #/^[^.].*$/ #t)))
    };
    my $rec; $rec = sub {
        my ($node, $matcher, $seed) = @_;
        my $current = $matcher->[0];
        if (!defined $current) {
            dbg("FINISHED");
            return $seed;
        } elsif (ref($current) eq 'SCALAR' && $current == $DEEPFLAG) {
            dbg("** mode");
            return $recstar->($node, cdr($matcher), $seed);
        } elsif (@{cdr($matcher)}==0) {
            dbg("file name");
            # (folder proc seed node (car matcher) #f)
            return $folder->($proc, $seed, $node, $current, 0);
        } else {
            dbg "NORMAL MATCH";
            return $folder->(sub {
                my ($node, $seed) = @_;
                dbg("NEXT: ", $node, cdr($matcher));
                return $rec->($node, cdr($matcher), $seed);
            }, $seed, $node, $current, 1);
            # (folder (lambda (node seed) (rec node (cdr matcher) seed))
            #                    seed node (car matcher) #t)
        }
    };
    my ($node, $matcher) = glob_prepare_pattern($pattern);
    dbg("pattern: ", $node, $matcher);
    return $rec->($node, $matcher, $seed);
}

# /^home$/ のような固定の文字列の場合に高速化をはかるための最適化なので、とりあえず undef をかえしておいても問題がない
sub fixed_regexp_p {
    return undef;
    die "TBI"
}

sub make_glob_fs_fold {
    my ($root_path, $current_path) = @_;
    my $ensure_dirname = sub {
        my $s = shift;
        if (defined($s) && length($s) > 0 && $s =~ m{$SEPCHAR$}) {
            $s .= $SEPCHAR;
        }
        return $s;
    };
    $root_path = $ensure_dirname->($root_path);
    $current_path = $ensure_dirname->($current_path);
    
    # returns arrayref of seeds.
    sub {
        my ($proc, $seed, $node, $regexp, $non_leaf_p) = @_;
        my $prefix = do {
            if (ref $node eq 'SCALAR') {
                if ($$node eq 1) { #t
                    $root_path || $SEPCHAR
                } elsif ($$node eq '0') { #f
                    $current_path || '';
                } else {
                    die "FATAL";
                }
            } else {
                $node . '/';
            }
        };
        dbg("prefix: $prefix");
        dbg("regxp: ", $regexp);
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
            dbg("normal regexp");
            my $dir = do {
                if (ref($node) eq 'SCALAR' && $$node eq 1) {
                    $root_path || $SEPCHAR
                } elsif (ref($node) eq 'SCALAR' && $$node eq 0) {
                    $current_path || '.';
                } else {
                    $node;
                }
            };
            dbg("dir: $dir");
            opendir my $dirh, $dir or do {
                dbg("cannot open dir: $dir: $!");
                return $seed;
            };
            while (my $child = readdir($dirh)) {
                next if $child eq '.' or $child eq '..';
                my $full;
                dbg("non-leaf: ", $non_leaf_p);
                if (($child =~ $regexp) && ($full = $prefix . $child) && (!$non_leaf_p || -d $full)) {
                    dbg("matched: ", $regexp, $child, $full);
                    $seed = $proc->($full, $seed);
                } else {
                    dbg("Don't match: $child");
                }
            }
            return $seed;
        }
    };
#   (define root-path/    (ensure-dirname root-path))
#   (define current-path/ (ensure-dirname current-path))
#   (lambda (proc seed node regexp non-leaf?)
#     (let1 prefix (case node
#                    [(#t) (or root-path/ separ)]
#                    [(#f) (or current-path/ "")]
#                    [else (string-append node separ)])
#       ;; NB: we can't use filter, for it is not built-in.
#       ;; also we can't use build-path from the same reason.
#       ;; We treat fixed-regexp specially, since it allows
#       ;; us not to search the directory---sometimes the directory
#       ;; has 'x' permission but not 'r' permission, and it would be
#       ;; unreasonable if we fail to go down the path even if we know
#       ;; the exact name.
#       (cond [(eq? regexp 'dir?) (proc prefix seed)]
#             [(fixed-regexp? regexp)
#              => (^s (let1 full (string-append prefix s)
#                       (if (and (file-exists? full)
#                                (or (not non-leaf?)
#                                    (file-is-directory? full)))
#                         (proc full seed)
#                         seed)))]
#             [else
#              (fold (lambda (child seed)
#                      (or (and-let* ([ (regexp child) ]
#                                     [full (string-append prefix child)]
#                                     [ (or (not non-leaf?)
#                                           (file-is-directory? full)) ])
#                            (proc full seed))
#                          seed))
#                    seed
#                    (sys-readdir (case node
#                                   [(#t) (or root-path/ "/")]
#                                   [(#f) (or current-path/ ".")]
#                                   [else node])))])))
#   ))
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

1;
__END__

=encoding utf8

=head1 NAME

File::Zglob -

=head1 SYNOPSIS

  use File::Zglob;

=head1 DESCRIPTION

File::Zglob is

=head1 LIMITATIONS

Only support UNIX-ish systems.

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom AAJKLFJEF GMAIL COME<gt>

=head1 SEE ALSO

L<File::DosGlob>, L<Text::Glob>

=head1 LICENSE

Copyright (C) Tokuhiro Matsuno

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
