use strict;
use warnings;

package AnyEvent::SCGI::Client;

use AnyEvent;
use AnyEvent::Handle;
use List::AllUtils 'reduce';
use namespace::clean;

use Sub::Exporter -setup => {
    exports => ['scgi_request'],
    groups  => { default => ['scgi_request'] },
};

sub scgi_request {
    my ($connect, $env, $body, $cb) = @_;

    my @env = (
        CONTENT_LENGTH => defined $body ? length $body : 0,
        SCGI => 1, %{ $env || {} },
    );

    my $req = (reduce { sprintf "%s\0%s", $a, $b } @env) . "\0";

    my $h;
    $h = AnyEvent::Handle->new(
        (ref $connect eq ref []
             ? 'connect' : 'fh') => $connect,
        on_connect => sub {
            $h->push_write(netstring => $req);
            $h->push_write($body) if defined $body;
            $h->push_shutdown;
        },
        on_read => sub {
            $cb->(\$h->{rbuf});
            undef $h;
        },
    );
}

1;
