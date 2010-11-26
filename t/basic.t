use strict;
use warnings;
use Test::More;
use Test::TCP;
use HTTP::Headers;
use HTTP::Response;
use AnyEvent::Impl::Perl; # EV is really broken, and it happens to be the
                          # default choice of AnyEvent much too often, so we
                          # just explicitly load something we know actually
                          # works most of the time and doesn't require a huge
                          # test dependency such as POE
use AnyEvent;
use AnyEvent::SCGI;
use Storable 'freeze', 'thaw';

use AnyEvent::SCGI::Client;

my $port = empty_port;
my $s = scgi_server '127.0.0.1', $port, sub {
    my ($handle, $env, $content, $fatal, $err) = @_;

    if ($fatal) {
        fail "unexpected $err";
        done_testing;
        exit;
    }

    my $headers = HTTP::Headers->new(
        'Status'       => 200,
        'Content-Type' => 'text/plain',
        'Connection'   => 'close',
    );

    $handle->push_write(
        join qq{\r\n} => (
            "Status: 200 OK",
            $headers->as_string,
            freeze {
                env  => $env,
                body => $content,
            }
        )
    );

    my $t;
    $t = AnyEvent->timer(after => 2, cb => sub {
        $handle->push_write(';');
        $t = AnyEvent->timer(after => 2, cb => sub {
            $handle->push_shutdown(1);
            undef $t;
        });
    });
};

sub test_scgi {
    my ($env, $body) = @_;

    my $cv = AnyEvent->condvar;
    {
        my $data;

        scgi_request '127.0.0.1', $port, $env, $body, sub {
            my ($chunk) = @_;

            if (defined $chunk) {
                $data .= $chunk;
            }
            else {
                $cv->send($data);
            }
        };
    }


    my $data = $cv->recv;
    ok $data, 'got response';

    my $resp = HTTP::Response->parse($data);
    ok $resp, 'response looks like http';

    is $resp->code, 200, 'status code';

    my $content = $resp->content;
    is substr($content, length($content) - 1, 1, ''), ';', 'got last write';

    is_deeply thaw($content), {
        body => \(ref $body
                      ? do {
                          my $fh = $body->[1];
                          seek $fh, 0, 0; local $/;
                          <$fh>;
                      }
                      : $body),
        env  => {
            CONTENT_LENGTH => ref $body ? -s $body->[1] : length $body,
            SCGI           => 1,
            %{ $env },
        },
    }, 'got right env and body';
}

test_scgi { moo => 23 }, "foo";

# a big-ish file that's around on pretty every system
require CPAN;
open my $fh, '<', $INC{'CPAN.pm'};
test_scgi { moo => 42 }, [-s $fh, $fh];

done_testing;
