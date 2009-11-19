package MasonX::Plugin::Catalyst::ImportStash;
# ABSTRACT: Import the stash into all components

use strict;
use warnings;

use base qw(HTML::Mason::Plugin);

=head1 SYNOPIS

   # in your action:
   sub test : Local {
     my ( $self, $ctx ) = @_;
     $ctx->stash( deep_value => 'Foo' );
   }

   # in your request component (test.mhtml):
   <h1>Calling deep value handler:</h1>
   <& some_deep_value_handler, direct_value => 'Bar' &>

   # in some_deep_value_handler
   <%args>
     $direct_value
     $deep_value
   </%args>
   <% $deep_value . $direct_value %>
   <%doc> prints FooBar as expected </%doc>

=head1 DESCRIPTION

Mason components that are not in the wrapper chain (i.E. all components
except autohandlers and those called by C<$m->call_next>) don't get
an accessible copy of the request args. This makes sense when you are
using Mason as a stand-alone application provider and request args get
set according to the HTTP request and thus are totally uncontrollable,
and all model and controller functionallity tends to be placed near the
hand-off.

In a Catalyst context this is cumbersome: you control the args
passed to Mason anyways and value retrieval happens far from the call to
the resp. component that will act as view for them. This plugin tries to
make things a little more pleasant in providing all components (excluding
subcomponents) with a copy of all non-private stash variables as args.

=cut

my $interface_check_done;

sub start_request_hook {
  my ( $self, $context ) = @_;

  unless ( $interface_check_done ) {
    my $meta = eval{ Class::MOP::class_of( $self->request_class )};
    my $api_ok = $meta&&$meta->does_role('MasonX::RequestContext::Catalyst');
    die ref($self) . " needs a MasonX::RequestContext::Catalyst enabled " .
      "request instance to work properly" unless $api_ok;
    $interface_check_done = 1;
  }

  # get (another!) copy of all non-private values in the stash
  my $stash = $context->request->catalyst_ctx->stash;
  my @sargs = map{ $_ => $stash->{$_} } grep{!/^_/} keys %$stash;

  # prepare the notes we will use during this request
  $context->request->notes( '__mp_cis_stash', \@sargs );
  $context->request->notes( '__mp_cis_modified_comps', {} )
    unless defined $context->request->notes( '__mp_cis_modified_comps' );

}

sub start_component_hook {
  my ($self, $context) = @_;
  my $comp = $context->comp;

  # ignore subcomponents
  return if $comp->is_subcomp;

  # components in the call chain already
  # get all request args and thus the stash
  return if exists $context->request->{wrapper_index}{ $comp->comp_id };

  # do nothing if the resp. conponent isn't
  # interested in named arguments
  return unless %{ $comp->declared_args };

  my $sargs = $context->request->notes( '__mp_cis_stash' );

  # mark this component so we can restore the arg list later on
  $context->request->notes( '__mp_cis_modified_comps' )->{ $comp } = 1;

  unshift @{ $context->args }, @{ $sargs };

}

sub end_component_hook {
  my ( $self, $context ) = @_;
  my $comp = $context->comp;

  # fetch and unset components modification status from
  # request notes, return if there is nothing to do
  delete $context->request->notes( '__mp_cis_modified_comps' )->{$comp}
   or return;

  my $sargs = $context->request->notes( '__mp_cis_stash' );

  # remove stash from argument list (this is fatal if a component
  # has mucked around with the aliased @_ while also using named
  # arguments, but anyone doing this doesn't deserve better)
  splice @{ $context->request->args }, 0, scalar @$sargs;

}

sub end_request_hook {
  my ( $self, $context ) = @_;
  # in theory these should die with the current request, but I
  # still want to unset them explicitly here to avoid potential
  # circular references
  $context->request->notes( '__mp_cis_stash', undef );
  $context->request->notes( '__mp_cis_modified_comps', undef )
}

1;

__END__

=head1 CAVEATS

Although L<HTML::Mason::Plugin> warns that a plugin may NOT modify args,
I have had no problems at all with at least five low to medium profile
websites in production. Consider yourself warned, nontheless!

Do not use named parameters in conjunction with modifying @_ in your
components. Not that this needed to be mentioned, $deity kills a
kitten everytime you do so, anyways.

=cut
