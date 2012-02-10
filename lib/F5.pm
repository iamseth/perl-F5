package F5;

use strict;
use warnings;
use SOAP::Lite;

our $VERSION = '1.1';

# Adding support for custom serializers. I have to override typcast so I'm
# removing warnings for this block.

{
    no warnings;

    my $urn_map = {
        '{urn:iControl}LocalLB.MonitorStatus'         => 1,
        '{urn:iControl}System.Failover.FailoverState' => 1,
        '{urn:iControl}LocalLB.ProfileContextType' => 1,
        '{urn:iControl}LocalLB.ProfileMode'        => 1,
        '{urn:iControl}LocalLB.ProfileType'        => 1,

    };

    sub SOAP::Deserializer::typecast {
        my ( $self, $value, $name, $attrs, $children, $type ) = @_;
        my $retval = undef;

        if ( not defined $type or not defined $urn_map->{$type} ) {
            return $retval;
        }

        if ( $urn_map->{$type} == 1 ) { $retval = $value }
        return $retval;
    }
}

sub new {

    my ( $class, $host ) = @_;
    my $self = bless {}, $class;

    # TODO - add some sort of checking here to ensure username,
    # password, and host are set.

    $self->{username} = $ENV{'F5_USER'};
    $self->{password} = $ENV{'F5_PASS'};

    if ( !defined $self->{username} ) { print "F5_USER not set!\n"; exit(2); }
    if ( !defined $self->{password} ) { print "F5_PASS not set!\n"; exit(2); }

    $self->{_client} =
      SOAP::Lite->proxy( 'https://'
          . $self->{username} . ':'
          . $self->{password} . '@'
          . $host . ':443'
          . '/iControl/iControlPortal.cgi' )
      ->deserializer( SOAP::Deserializer->new() );

    return $self;
}

sub username {

    my ( $self, $username ) = @_;

    if ( defined $username ) {
        $self->{username} = $username;
    }

    return $self->{username};
}

sub password {

    my ( $self, $password ) = @_;

    if ( defined $password ) {
        $self->{password} = $password;
    }

    return $self->{password};
}

sub host {

    my ( $self, $host ) = @_;

    if ( defined $host ) {
        $self->{host} = $host;
    }

    return $self->{host};
}

sub _request {

    my ( $self, %args ) = @_;

    my @params = ();

    foreach my $arg ( keys %{ $args{data} } ) {
        if ( ref $args{data} eq 'HASH' ) {
            push @params, SOAP::Data->name( $arg => $args{data}{$arg} );
        }
        else {
            push @params, SOAP::Data->name( %{ $args{data} } );
        }
    }

    $self->{_client}->uri("urn:iControl:$args{module}/$args{interface}");

    my $method = $args{method};
    my $query  = $self->{_client}->$method(@params);
    undef $self->{_client}->{uri};

    if ( defined $query->fault ) {
        return $query->fault;
    }

    return $query->result;
}

sub fetch_all_pools {

    return @{
        $_[0]->_request(
            module    => 'LocalLB',
            interface => 'Pool',
            method    => 'get_list'
        )
      };
}

sub __fetch_pool_members {

    my ( $self, $pool, $module ) = @_;
    return $self->_request(
        module    => $module,
        interface => 'Pool',
        method    => 'get_member',
        data      => { pool_names => [$pool] }
    );
}

sub fetch_pool_members {

    my ( $self, $pool, $noresolve ) = @_;

    my @members;

    foreach ( @{ @{ $self->__fetch_pool_members( $pool, 'LocalLB' ) }[0] } ) {
        my $address;

        if ($noresolve) {
            $address = $_->{address};
        }
        else {
            $address = $self->ip_to_hostname( $_->{address} );
        }

        push @members, ( { address => $address, port => $_->{port} } );
    }

    return @members;
}

sub add_member_to_pool {

    my ( $self, $address, $port, $pool_name ) = @_;

    my $member = {
        address => $address,
        port    => $port
    };

    push( my @memberA, $member );
    push my @memberAofA, [@memberA];

    return $self->_request(
        module    => 'LocalLB',
        interface => 'Pool',
        method    => 'add_member',
        data      => { pool_names => [$pool_name], members => [@memberAofA] }
    );

}

sub remove_member_from_pool {

    my ( $self, $address, $port, $pool_name ) = @_;

    my $member = {
        address => $address,
        port    => $port
    };

    push( my @memberA, $member );
    push my @memberAofA, [@memberA];
    return $self->_request(
        module    => 'LocalLB',
        interface => 'Pool',
        method    => 'remove_member',
        data      => { pool_names => [$pool_name], members => [@memberAofA] }
    );

}

sub fetch_pool_member_status {

    my ( $self, $pool ) = @_;

    my $status = $self->_request(
        module    => 'LocalLB',
        interface => 'PoolMember',
        method    => 'get_monitor_status',
        data      => {
            pool_names => [$pool],
            members    => $self->__fetch_pool_members( $pool, 'LocalLB' )
        }
    );

    # The typical request returns some weird object. I intend to convert to a
    # normal array here.

    my @returned;

    foreach my $i ( @{$status} ) {
        foreach ( @{$i} ) {
            my $status = $_->{monitor_status};
            my $member = $_->{member}->{address} . ":" . $_->{member}->{port};
            push( @returned, { $member => $status } );
        }
    }

    return @returned;

}

sub fetch_all_vips {

    my ($self) = @_;

    return $self->_request(
        module    => 'LocalLB',
        interface => 'VirtualServer',
        method    => 'get_list'
    );
}

sub fetch_vip_destination {

    my ( $self, $vip ) = @_;

    my @dest = $self->_request(
        module    => 'LocalLB',
        interface => 'VirtualServer',
        method    => 'get_destination',
        data      => { virtual_servers => [$vip] }
    );

    return $dest[0][0]{address} . ":" . $dest[0][0]{port};
}

sub create_pool {

    my ( $self, $pool_name ) = @_;

    # I can't figure out how to make a blank pool so I create a bogus member
    # and remove after creation.

    my $member = {
        address => '10.0.0.1',
        port    => 1337
    };

    push( my @memberA, $member );
    push my @memberAofA, [@memberA];

    my $response = $self->_request(
        module    => 'LocalLB',
        interface => 'Pool',
        method    => 'create',
        data      => {
            pool_names => [$pool_name],
            lb_methods => ['LB_METHOD_LEAST_CONNECTION_MEMBER'],
            members    => [@memberAofA]
        }
    );

    # Now I remove the bogus member.
    $self->remove_member_from_pool( $member, $pool_name );
    return $response;
}

sub remove_pool {

    my ( $self, $pool_name ) = @_;

    return $self->_request(
        module    => 'LocalLB',
        interface => 'Pool',
        method    => 'delete_pool',
        data      => { pool_names => [$pool_name] }
    );
}

sub fetch_static_routes {

    my ($self) = @_;

    my @routes = $self->_request(
        module    => 'Networking',
        interface => 'RouteTable',
        method    => 'get_static_route'
    );

    my @routes_cleaned;

    foreach my $i (@routes) {
        foreach ( @{$i} ) {
            my $route_def = {
                'destination' => $_->{destination},
                'netmask'     => $_->{netmask}
            };

            push( @routes_cleaned, $route_def );
        }
    }

    return @routes_cleaned;
}

sub _convert_ip_to_network {

    my ( $self, $ip_address ) = @_;
    my @x = split( /\./, $ip_address );
    $x[3] = 0;
    my $network = join( '.', @x );

    return $network;
}

sub route_exists {

    my ( $self, $ip_address ) = @_;

    my @all_routes = $self->fetch_static_routes();
    my $network    = $self->_convert_ip_to_network($ip_address);

    for my $route (@all_routes) {
        if ( $route->{destination} eq $network ) {
            return 1;
        }
    }

    return 0;
}

sub add_static_route {

    my ( $self, $destination, $netmask, $gateway ) = @_;

    my $route = { destination => $destination, netmask => $netmask };

    my $attributes = {
        gateway   => $gateway,
        vlan_name => '',
        pool_name => ''
    };

    return $self->_request(
        module    => 'Networking',
        interface => 'RouteTable',
        method    => 'add_static_route',
        data      => {
            routes     => [$route],
            attributes => [$attributes],
        }
    );
}

sub remove_static_route {

    my ( $self, $destination, $netmask ) = @_;
    my $route = { destination => $destination, netmask => $netmask };

    return $self->_request(
        module    => 'Networking',
        interface => 'RouteTable',
        method    => 'delete_static_route',
        data      => { routes => [$route] }
    );

}

sub get_failover_state {

    my ($self) = @_;

    return $self->_request(
        module    => 'System',
        interface => 'Failover',
        method    => 'get_failover_state'
    );

}

sub is_active {

    my ($self) = @_;

    my $status = $self->get_failover_state();
    if ( $status =~ m/active/i ) {
        return 1;
    }

    return 0;
}

sub create_virtual_server {

    my ( $self, $name, $address, $port, $pool ) = @_;

    my $definition = {
        name     => $name,
        address  => $address,
        port     => $port,
        protocol => 'PROTOCOL_TCP'
    };

    my $wildmask = '255.255.255.255';

    my $resource = {
        type              => 'RESOURCE_TYPE_POOL',
        default_pool_name => $pool
    };

    my $profile = {
        profile_context => 'PROFILE_CONTEXT_TYPE_ALL',
        profile_name    => 'tcp-http',
        profile_type    => 'PROFILE_TYPE_TCP'
    };

    my $profile2 = {
        profile_context => 'PROFILE_CONTEXT_TYPE_ALL',
        profile_name    => 'http',
        profile_type    => 'PROFILE_TYPE_HTTP'
    };

    my $response = $self->_request(
        module    => 'LocalLB',
        interface => 'VirtualServer',
        method    => 'create',
        data      => {
            definitions => [$definition],
            wildmasks   => [$wildmask],
            resources   => [$resource],
            profiles    => [ [ $profile, $profile2 ] ]
        }
    );

    # if we get a response, it's not good. return early
    if ($response) {
        return $response;
    }

}

sub remove_virtual_server {

    my ( $self, $virtual_server ) = @_;

    return $self->_request(
        module    => 'LocalLB',
        interface => 'VirtualServer',
        method    => 'delete_virtual_server',
        data      => { virtual_servers => [$virtual_server] }
    );
}

sub ip_to_hostname {
    my ( $self, $ip_address ) = @_;

    my @hostname = $self->_request(
        module    => 'System',
        interface => 'Inet',
        method    => 'ip_to_hostname',
        data      => { ip_addresses => [$ip_address] }
    );

    return $hostname[0][0];
}

sub hostname_to_ip {

    my ( $self, $hostname ) = @_;

    my @ip_address = $self->_request(
        module    => 'System',
        interface => 'Inet',
        method    => 'hostname_to_ip',
        data      => { hostnames => [$hostname] }
    );

    return $ip_address[0][0];

}

1;

__END__

=head1 NAME

F5 - Module for interacting with F5's BigIP load balancers

=head1 SYNOPSIS

=head1 DESCRIPTION

=head2 Methods

=over 12

=item C<new>

Returns a new F5 object.

=item C<username>

Sets the username.

=item C<password>

Sets the password.

=item C<host>

Server hostname where the balancer can be found.

=item C<_request>

Generic request method for internal use only.

=item C<fetch_all_pools>

Retrieve a list of all pools.

=item C<__fetch_pool_members>

Private method for helping with the public version fetch_pool_members.

=item C<fetch_pool_members>

Takes a pool name and returns all members within that pool.

    my $pool_name = 'test-pool';

    foreach my $member ( $f5->fetch_pool_members($pool_name) ) {
        print "\t$member\n";
    }   

=item C<add_member_to_pool>

Adds a member to an existing pool.

    my $member = {host => '10.0.0.1', port => 80};
    my $pool_name = 'test-pool';

    $f5->add_member($member, $pool_name);

=item C<remove_member_from_pool>

Remove a member from a pool.

    my $member = {host => '10.0.0.1', port => 80};
    my $pool_name = 'test-pool';

    $f5->remove_member($member, $pool_name);

=item C<fetch_pool_member_status>

Returns all members and their status's from a given pool.

    my $pool_name = 'test-pool';
    my $stat = $f5->fetch_pool_member_status($pool_name);
    print Dumper($stat);

=item C<fetch_all_vips>

Returns a list of all virtual servers (vips)

=item C<fetch_vip_destination>

Returns the destination address for a particular virtual server (vip)

    my $vip_name = 'test-vip';
    my $destination = $f5->fetch_vip_destination($vip_name);

=item C<create_pool>

Creates a new empty pool.

    my $new_pool_name = 'testing2-pool';
    $f5->create_pool($new_pool_name);

=item C<remove_pool>

Removes an entire pool.

    my $pool_name = 'testing2-pool';
    $f5->remove_pool($pool_name);

=item C<fetch_static_routes>

Returns a list of hashes of all static routes in balancer.

=item C<_convert_ip_to_network>

Internal subroutine for converting IP addresses into /24 network blocks.

=item C<route_exists>

Returns true if a route exists for the given IP.

    if ( ! $f5->route_exists('10.50.50.50') ) {
        $f5->add_static_route('10.50.50.0', '255.255.255.0')
    } else {
        print "Route already exists, skipping\n";
    }

=item C<add_static_route>

Adds the specified static route entries to the route table.

    $f5->add_static_route('10.50.50.0', '255.255.255.0')

=item C<remove_static_route>

Deletes the specified static route entries from the route table.

    $f5->remove_static_route('10.50.50.0', '255.255.255.0')

=item C<ip_to_hostname>

Translate the specified IP address into a hostname.

=item C<hostname_to_ip>

Converts the specified hostname to a IP address.

=item C<get_failover_state>

Returns the full state of failover for the balancer.

=item C<is_active>

Returns 1 if balancer is active and 0 otherwise.

=item C<create_virtual_server>

Creates or updates virtual servers from the specified resources. 

    my $name = 'aaa-justtesting';
    my $address = '10.0.0.5';
    my $port = 5555;
    my $pool = 'mypool';

    $f5->create_virtual_server($name, $address, $port, $pool));

=item C<remove_virtual_server>

Deletes the specified virtual server.

    $f5->remove_virtual_server('aaa-justtesting');

=back

=head1 AUTHOR

Seth Miller <seth@migrantgeek.com>

=cut

