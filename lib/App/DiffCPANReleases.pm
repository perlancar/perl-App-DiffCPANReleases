package App::DiffCPANReleases;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

our %SPEC;

sub _get_release {
    require File::Util::Tempdir;

    my $rel = shift;
    log_trace "Resolving %s ...", $rel;

    my $tempdir = File::Util::Tempdir::get_tempdir();

  USE_PATH:
    {
        if ($rel =~ m!/! || $rel =~ /\.tar(\.\w+)?\z/) {
            return [404, "No such release tarball file '$rel'"] unless -f $rel;
            return [200, "OK (file)", $rel];
        }
    }

    my ($dist, $ver);
    if ($rel =~ /\A(\w+(?:-\w+)*)\@([0-9][\w.-]*)\z/) {
        $dist = $1;
        $ver = $2;
    } elsif ($rel =~ /\A\w+(?:-\w+)*\z/) {
        $dist = $rel;
    } else {
        return [400, "Invalid release syntax: $rel, please use ".
                    "path or DISTNAME\@VERSION or DISTNAME"];
    }

  USE_CACHE:
    {
        last unless $ver;
        for my $ext (qw/.tar.gz .tar.bz2 .tar.xz .tar/) {
            my $path = "$tempdir/$dist-$ver$ext";
            return [200, "OK (cached URL)", $path] if -f $path;
        }
    }

    my $url;
  RESOLVE:
    {
        require App::cpm::Resolver::MetaCPAN;
        my $resolver = App::cpm::Resolver::MetaCPAN->new;
        (my $pkg = $dist) =~ s/-/::/g;
        my $version_range; $version_range = "==$ver" if defined $ver;
        my $res = $resolver->resolve({
            package => $pkg,
            (version_range => $version_range) x !!(defined $version_range),
        });
        log_trace "Result from MetaCPAN resolver: %s", $res;
        return [500, "Can't resolve $rel: $res->{error}"] if $res->{error};
        $url = $res->{uri};
    }

  DOWNLOAD:
    {
        my ($filename) = $url =~ m!.+/([^/]+)\z!;
        $filename or return [412, "BUG? Can't extract filename from URL $url"];
        my $path = "$tempdir/$filename";
        return [200, "OK (cached URL)", $path] if -f $path;

        require HTTP::Tiny;
        log_trace "Downloading %s ...", $url;
        my $res = HTTP::Tiny->new->get($url);
        return [$res->{status}, "Can't download $url: $res->{reason}"]
            unless $res->{success};

        open my $fh, ">", $path or return [500, "Can't open $path: $!"];
        binmode($fh);
        print $fh $res->{content};
        close $fh or return [500, "Can't write $path: $!"];
        return [200, "(downloaded URL)", $path];
    }
}

$SPEC{diff_cpan_releases} = {
    v => 1.1,
    summary => 'Diff contents of two CPAN releases',
    description => <<'_',

For the release, you can enter a tarball filename/path (e.g.
`Foo-Bar-1.23.tar.gz` or `/tmp/Foo-Bar-4.567.tar.bz2`) or just a distname
followed by `@` and version number (e.g. `Foo-Bar@1.23`) or just a distname
(e.g. `Foo-Bar`) to mean the latest release of a distribution. The release
tarballs will be downloaded (except when you already specify a tarball path)
then diff-ed using <pm:App::DiffTarballs>.

_
    args => {
        release1 => {
            schema => 'str*',
            req => 1,
            pos => 0,
        },
        release2 => {
            schema => 'str*',
            req => 1,
            pos => 1,
        },
    },
    examples => [
        {
            argv => [qw/My-Dist@1.001 My-Dist@1.002/],
            summary => 'Download two Perl releases and diff them',
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            argv => [qw/My-Dist@1.001 My-Dist/],
            summary => 'Compare My-Dist 1.001 vs the latest',
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
};
sub diff_cpan_releases {
    require App::DiffTarballs;

    my %args = @_;

    my $res;

    $res = _get_release($args{release1});
    return $res unless $res->[0] == 200;
    my $tarball1 = $res->[2];

    $res = _get_release($args{release2});
    return $res unless $res->[0] == 200;
    my $tarball2 = $res->[2];

    log_trace "tarball1=%s, tarball2=%s", $tarball1, $tarball2;

    App::DiffTarballs::diff_tarballs(
        tarball1 => $tarball1, tarball2 => $tarball2);
}

1;
# ABSTRACT:

=head1 SYNOPSIS

See the included script L<diff-cpan-releases>.
