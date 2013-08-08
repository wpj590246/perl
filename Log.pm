package Log;

use strict;
use warnings;

use FileHandle;
use Encode;
use Data::Dumper;

=head1 package usage

my $log = Log->new('./', 'name', 1);
$log->sayshort('lalala');
$log->err('lalala');

=cut

sub new{
	
	my $class = shift;
	my $path = shift;
	my $name = shift;
	my $add_date_to_logfilename = shift;
	
	my $logfilename = $add_date_to_logfilename ? $name . get_date() : $name;
	my $say_fh = FileHandle->new($path . $logfilename . '.log', '>>');
	$say_fh->autoflush(1);
	my $err_fh = FileHandle->new($path . $logfilename . '.err', '>>');
	$err_fh->autoflush(1);
	my $self = bless {say => $say_fh, err => $err_fh}, $class;
	
	return $self;
}

sub sayshort{
	
	my $self = shift;
	my $sentence = shift;
	my $tm = get_time();
	$sentence = encode_utf8($sentence) if Encode::is_utf8($sentence);
	
	$self->{say}->print("$tm\t$$\t$sentence\n");
}	

sub say{
	
	my $self = shift;
	my $sentence = shift;
	my $ra_dp = shift;
	my $ra_dp_var = shift;
	my $tm = get_time();
	$sentence = encode_utf8($sentence) if Encode::is_utf8($sentence);
	
	my $caller = &get_caller();
	my $cur_caller = &get_current_caller();
	
	$self->{say}->print("$tm\t$$\t$cur_caller->{filename}::$cur_caller->{sub} say \"$sentence\" @ line $cur_caller->{line}\n");	
	
	$self->{say}->print(&get_dumper($ra_dp, $ra_dp_var)) if $ra_dp;
}

sub err{
	
	my $self = shift;
	my $sentence = shift;
	my $ra_dp = shift;
	my $ra_dp_var = shift;
	my $tm = get_time();
	$sentence = encode_utf8($sentence) if Encode::is_utf8($sentence);
	
	# err在log里面也记录一下
	
	$self->say($sentence, $ra_dp, $ra_dp_var);
	
	my $caller = &get_caller();
	my $cur_caller = &get_current_caller();
	
	$self->{err}->print("$tm\t$$\t$cur_caller->{filename}::$cur_caller->{sub} ERROR \"$sentence\" @ line $cur_caller->{line}\n");	
	
	$self->{err}->print("#" x 8 . " Caller " . "#" x 65 . "\n");
	for (reverse(0..$#$caller)){
		my $n_caller = $caller->[$_];
		$self->{err}->print("#\t" . "caller : $n_caller->{filename}::$n_caller->{sub} @ line $n_caller->{line}\n");
	}
	
	$self->{err}->print(&get_dumper($ra_dp, $ra_dp_var)) if $ra_dp;
}

sub get_time{
	
	my ($sec, $min, $hour, $day, $mon, $year) = localtime;
	$mon++;
	$year += 1900;
	
	for (($mon, $day, $hour, $min, $sec)){
		$_ = '0' . $_ if $_ < 10;
	}
	
	return "$year-$mon-$day $hour:$min:$sec";
}

sub get_date{
	
	my (undef, undef, undef, $day, $mon, $year) = localtime;
	$mon++;
	$year += 1900;
	
	for (($mon, $day)){
		$_ = '0' . $_ if $_ < 10;
	}
	
	return "$year-$mon-$day";
}

sub get_caller{
	
	my $return_v;
	
	my $stack_lv = 2;
	while(1){
		my @info = caller($stack_lv++);
		last unless(@info);
		next if ($info[3] =~ /eval/);
		
		push @$return_v, {filename => $info[1], line => $info[2], sub => $info[3]};	
	}
	
	return $return_v;
}

sub get_current_caller{
	
	my $sub = (scalar caller(2) and ( caller(2) )[3]) ? ( caller(2) )[3] : '';
	$sub =  ( caller(3) )[3] if $sub =~ /eval/;
	my ($filename, $line) = ( caller(1) )[1..2];
	
	return {filename => $filename, line => $line, sub => $sub};
}

sub get_dumper{
	
	my $ra_dp = shift;
	my $ra_dp_var = shift;

	my $dumper = Data::Dumper->new($ra_dp, $ra_dp_var);
	my $return_v = "*" x 8 . " Dumper " . "*" x 65 . "\n";
	my $dp_result .= $dumper->Dump();
	$dp_result =~ s/(.*?)\n/*\t$1\n/g;
	$return_v .= $dp_result . "\n";
	
	return $return_v;
}	

1;

