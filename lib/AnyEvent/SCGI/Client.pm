use strict;
use warnings;

package AnyEvent::SCGI::Client;
# ABSTRACT: Event-based SCGI client

use AnyEvent;
use AnyEvent::Socket;
use namespace::clean;

use Sub::Exporter -setup => {
    exports => ['scgi_request'],
    groups  => { default => ['scgi_request'] },
};

=func scgi_request ($connect, \%env, $body | [$length, $fh], $cb->(), ...)

=cut

sub scgi_request {
    my ($host, $service, $env, $_body, $cb, @more) = @_;

    my ($body_len, $body) = ref $_body eq ref []
        ? @{ $_body } : (length $_body, $_body);

    my @env = (
        CONTENT_LENGTH => $body_len,
        SCGI => 1, %{ $env || {} },
    );

    my $req = join "\0" => @env, '';
    my $buf = (length $req) . ":$req,";
    $buf .= $body if $body && !ref $body;

    my $s;
    $s = tcp_connect $host, $service, sub {
        my ($fh) = @_ or die "connect failed: $!";

        my ($w, $bw);
        my $drain = sub {
            my $b = $fh->syswrite($buf, length $buf);
            die $! unless defined $b;

            substr $buf, 0, $b, '';

            if (!length $buf) {
                undef $w;
            }

            if (ref $body && !$bw || !ref $body) {
                shutdown $fh, 1;
            };
        };

        if ($body && ref $body) {
            $bw = AnyEvent->io(fh => $body, poll => 'r', cb => sub {
                my $b = $body->sysread(my $chunk, 8192);

                if ($b) {
                    $buf .= $chunk;
                    $w = AnyEvent->io(fh => $fh, poll => 'w', cb => $drain)
                        if !$w;
                }
                else {
                    undef $bw;
                }
            });
        }

        $w = AnyEvent->io(fh => $fh, poll => 'w', cb => $drain);

        my $r;
        $r = AnyEvent->io(fh => $fh, poll => 'r', cb => sub {
            my $b = $fh->sysread(my $chunk, 8192);

            if ($b) {
                $cb->($chunk);
            } else {
                undef $r;
                $cb->(undef);
                undef $s;
            }
        });
    };
}

1;
