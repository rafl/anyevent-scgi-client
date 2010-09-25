use strict;
use warnings;
use Test::More;
use Test::TCP;
use HTTP::Headers;
use HTTP::Response;
use POE; # EV is really broken, and it happens to be the default choice of
         # AnyEvent much too often, so we just explicitly load something we know
         # actually works
use AnyEvent;
use AnyEvent::SCGI;
use Data::Dump 'pp';

use AnyEvent::SCGI::Client;

my $port = empty_port;
my $s = scgi_server '127.0.0.1', $port, sub {
    my ($handle, $env, $content, $fatal, $err) = @_;

    my $headers = HTTP::Headers->new(
        'Status'       => 200,
        'Content-Type' => 'text/plain',
        'Connection'   => 'close',
    );

    $handle->push_write(
        join qq{\r\n} => (
            "Status: 200 OK",
            $headers->as_string,
            pp {
                env  => $env,
                body => $content,
            }
        )
    );
    $handle->push_shutdown;
};

open my $fh, '<', $0;

my $cv = AnyEvent->condvar;
scgi_request ['127.0.0.1', $port], { moo => 42 }, [-s $fh, $fh], sub {
    $cv->send($_[0]);
};

my $data = $cv->recv;
ok $data && $$data, 'got response';

my $resp = HTTP::Response->parse($$data);
ok $resp, 'response looks like http';

is $resp->code, 200, 'status code';

is_deeply eval $resp->content, {
    body => \do { seek $fh, 0, 0; local $/; <$fh> },
    env  => {
        CONTENT_LENGTH => -s $fh,
        SCGI           => 1,
        moo            => 42,
    },
}, 'got right env and body';

done_testing;
