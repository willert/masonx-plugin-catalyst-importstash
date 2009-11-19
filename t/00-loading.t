use Test::More;

use FindBin;
use lib "$FindBin::Bin/../lib";

sub use_ok_or_bail($) {
  use_ok $_[0] or BAIL_OUT( "Failed to load essential module $_[0]" );
}

use_ok_or_bail 'MasonX::Plugin::Catalyst::ImportStash';

done_testing();
