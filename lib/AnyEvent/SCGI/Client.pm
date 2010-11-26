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

=head1 SYNOPSIS

    use AnyEvent;
    use AnyEvent::SCGI::Client;

    my $cv = AnyEvent->condvar;

    {
        my $data;
        scgi_request '127.0.0.1', '22222', { REQUEST_METHOD => 'GET', ... }, undef, sub {
            my ($response_chunk) = @_;

            if (defined $response_chunk) {
                $data .= $response_chunk;
            }
            else {
                $cv->send($data);
            }
        };
    }

    my $response = $cv->recv;

=head1 DESCRIPTION

This module implements an event-based client for the Simple Common Gateway
Interface protocol, SCGI, using AnyEvent.

=func scgi_request ($host, $service, \%env, $body | [$length, $fh], $cb->($response_chunk))

Initiates an SCGI request to an SCGI server as specified by C<$host> and
C<$service>. See
L<AnyEvent::Socket/"$guard = tcp_connect $host, $service, $connect_cb[, $prepare_cb]">
for a description of possible values for C<$host> and C<$service>.

SCGI headers and their values can be provided in in the C<\%env> hash
reference. The C<SCGI> and C<CONTENT_LENGTH> headers required by the SCGI
specification will be provided automatically.

A request body can be provided as either a plain string or an array reference
containing the length of the body and a filehandle to read it from.

The callback C<$cb> will be called for every chunk of data received as the
response from the SCGI server. The callback takes on argument containing the
data received. C<$response_chunk> will be C<undef> to indicate when the SCGI
server closed the connection after sending its response.

This function is exported by default.

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

=head1 SEE ALSO

L<The SCGI specification|http://python.ca/scgi/protocol.txt>

L<AnyEvent::SCGI>

=cut

1;
