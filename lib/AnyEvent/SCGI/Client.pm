use strict;
use warnings;

package AnyEvent::SCGI::Client;
# ABSTRACT: Event-based SCGI client

use AnyEvent;
use AnyEvent::Handle;
use namespace::clean;

use Sub::Exporter -setup => {
    exports => ['scgi_request'],
    groups  => { default => ['scgi_request'] },
};

=func scgi_request ($connect, \%env, $body, $cb->())

=cut

sub scgi_request {
    my ($connect, $env, $_body, $cb) = @_;

    my ($body_len, $body) = ref $_body eq ref []
        ? @{ $_body } : (length $_body, $_body);

    my @env = (
        CONTENT_LENGTH => $body_len,
        SCGI => 1, %{ $env || {} },
    );

    my $req = join "\0" => @env, '';

    my $h;
    $h = AnyEvent::Handle->new(
        (ref $connect eq ref []
             ? 'connect' : 'fh') => $connect,
        on_connect => sub {
            $h->push_write(netstring => $req);

            if (defined $body && !ref $body) {
                $h->push_write($body);
                $h->push_shutdown;
            }
            else {
                my $fh;
                $fh = AnyEvent::Handle->new(
                    fh => $body,
                    on_read => sub {
                        $h->push_write($fh->{rbuf});
                        $fh->{rbuf} = '';
                    },
                    on_eof => sub {
                        $h->push_shutdown;
                        undef $fh;
                    },
                );
            }

        },
        on_read => sub {
            $cb->(\$h->{rbuf});
            undef $h;
        },
    );
}

1;
