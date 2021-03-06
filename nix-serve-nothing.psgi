use MIME::Base64;
use Nix::Config;
use String::ShellQuote;
use Getopt::Long;

use strict;

my %proxyOpts = (
    target => "",
    command => "",
    when => "",
    cachettl => 300,
);
my $useProxy = "";
my $proxy = 0;
my $checkedAt = 0;
GetOptions ('proxy-opts|p:s%{,}' => \%proxyOpts);

# we don't just check at startup so we can be lazy and wait for the state when
# first queried
sub checkUseProxy {
    my $now = time;

    if ($useProxy != "" || $now - $checkedAt < int($proxyOpts{'cachettl'})) {
        return $useProxy;
    }

    $checkedAt = $now;

    $useProxy = 0;

    if ($proxyOpts{'target'} != "") {
        $proxy = Plack::App::Proxy->new(remote => $proxyOpts{'target'})->to_app;

        my $cmd_ret_val = readpipe(shell_quote $proxyOpts{'command'});
        my $cmd_exit_code = $?;

        if ($proxyOpts{'when'} && $cmd_ret_val == $proxyOpts{'when'}) {
            $useProxy = 1;
        }

        elsif ($cmd_exit_code == 0) {
            $useProxy = 1;
        }
    }

    if ($useProxy == 1) {
        print(
            localtime($checkedAt)
            . ": Nix-serve-nothing set up to proxy to "
            . $proxyOpts{'target'}
            . ".\n"
        );
    }
    else {
        print(
            localtime($checkedAt)
            . ": Nix-serve-nothing set up without proxy.\n"
        );
    }

    return $useProxy;
}

my $app = sub {
    my $env = shift;

    my $path = $env->{PATH_INFO};

    if (checkUseProxy() == 1) {
        return $proxy->($env);
    }

    elsif ($path eq "/nix-cache-info") {
        return [200, ['Content-Type' => 'text/plain'], ["StoreDir: $Nix::Config::storeDir\nWantMassQuery: 1\nPriority: 30\n"]];
    }

    else {
        return [404, ['Content-Type' => 'text/plain'], ["File not found.\n"]];
    }
}