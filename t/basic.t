use strict;
use warnings;
use Test::More;
use Test::TCP;
use HTTP::Headers;
use HTTP::Response;
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
        sprintf "%s\r\n%s\r\n", $headers->as_string, pp {
            env  => $env,
            body => $content,
        }
    );
    $handle->push_shutdown;
};

my $cv = AnyEvent->condvar;
scgi_request ['127.0.0.1', $port], { moo => 42 }, 'kooh', sub {
    $cv->send($_[0]);
};

my $data = $cv->recv;
ok $data && $$data, 'got response';

my $resp = HTTP::Response->parse($$data);
ok $resp, 'response looks like http';

is_deeply eval $resp->content, {
    body => \'kooh',
    env  => {
        CONTENT_LENGTH => 4,
        SCGI           => 1,
        moo            => 42,
    },
}, 'got right env and body';

done_testing;
