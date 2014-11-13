package DB;

use strict;
use warnings;

use DBI;
use Data::Dumper;


=head1 package usage

my $db = new DB;
my $dbh = $db->get_dbh;

=cut

sub new(){
	my ($class, $newconfig) = @_;
	
	my $self = {};
	bless $self, $class;
	
	$config = $newconfig if($newconfig);
	return $self;
}



sub get_dbh(){
	
	my $self = shift;
	
	if($self->{dbh} and $self->{dbh}->ping()){
		return $self->{dbh};
	}
	else{
		$self->{dbh} = $self->connect('192.168.0.1', '3306', '*', '××', 'apollo');
		return $self->{dbh};
	}
}


sub get_front_dbh(){
	
	my $self = shift;
	
	if($self->{front_dbh} and $self->{front_dbh}->ping()){
		return $self->{front_dbh};
	}
	else{
		$self->{front_dbh} = $self->connect('192.168.0.12', '3306', '*', '××', 'apollo');
		return $self->{front_dbh};
	}
}

1;

