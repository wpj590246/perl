#! /usr/bin/perl -w
use strict;

use Encode;
use LWP::UserAgent;
use DBI;
use Data::Dumper;
use URI::Escape;
use JSON;
use FindBin qw($Bin);
use lib "$Bin/.";
use DB;
my $json = new JSON;
my $ref = {};
my $prop_ref = {};
my $pre_url = 'http://localhost:8983/solr/qbtSearch';
my $Limit_sales = 30000;
my $Limit_num_trade_divisor = 50;
my $run_mod = $ARGV[0] || 'insert';
my $testlab = $ARGV[1] || 0;

my $ua = LWP::UserAgent->new(
	agent => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; zh-CN; rv:1.9.0.9) Gecko/2009040821 Firefox/3.0.9',
	timeout => 3000,
	cookie_jar => {},
	max_redirect => 99,
);
my $child_f = {};
my $db = new DB;
&dieunless1();
open TTT, '>>', $Bin.'/perl_log/'.get_time(1).'.log';
$| = 1;
my $oldfh = select(TTT);
$| = 1;
select($oldfh);

my	$dbh_master ;
my	$dbh_front ;


if($run_mod eq 'insert') {
	&props_init unless $testlab;
	&solr_insert(0) unless $testlab;
	&solr_insert(1) ;
	&solr_delete unless $testlab;
	&solr_optimize unless $testlab;
} elsif ($run_mod eq 'delete') {
	&solr_delete;
} elsif($run_mod eq 'select') {
	&solr_select;
}




close TTT;
sub solr_insert{
	my $dbh_front_main  = $db->get_dbh_front();
	my $is_mall = shift || 0;
	my $table = $is_mall ? 'cur_item_mall' : 'cur_item' ;
	my $cal_id = 0;
	my $limit  = $is_mall ? 1000 : 3000;
	$limit = 10 if $testlab;
	solrlog('start solr insert type '.$table);
	
	solr_commit();
	my ($max_id) =$db->get_dbh_front()->selectrow_array("select id from $table order by id desc limit 1");
	solrlog('max id is '.$max_id);
	my $each_part = int($max_id/3);
	for(1..3){
			my $start_id = $each_part*($_-1);
			my $end_id = ($_ == 3) ? $max_id : $each_part*($_);
			
			if(my $pid = fork()){
				$child_f->{$pid} = 1;
			}
			else{	
				solrlog("fork child $$, " . join ' ', keys %$child_f);
				eval{
					&solr_insert_branch($is_mall,$table,$start_id,$end_id,$limit,);
				};
				if($@){
					solrlog("solr_insert_branch failed ERR $@");
				}
				solrlog("child $$ die");
				exit;
			}
	}
		

	while((my $pid = wait()) != -1){
		delete $child_f->{$pid};
	}
	
	solr_commit();
	solrlog('end solr insert');
}
sub solr_insert_branch{
	my ($is_mall,$table,$start_id,$end_id,$limit) = @_;
	$db = new DB;
	# $dbh_master  = $db->get_dbh();
	# $dbh_front  = $db->get_dbh_front();
	solrlog("start id is $start_id ,end id is $end_id");

	while (1){
		solrlog('start id '.$start_id);
		my $json1 = [];
	#	$prop_ref = {};
		my $sql = "SELECT c.id,c.tb_item_id,c.auction_id,c.cid,c.sid,c.sub_brand,c.name as g_name,c.price,c.brand,c.region,c.props,c.favorite_num,c.num_cur,c.num_cur_mon,c.num_last_mon,c.sales_cur,c.sales_cur_mon,c.sales_last_mon,c.trade_cur,c.trade_cur_mon,c.trade_last_mon,c.last_trade_time,s.nick,s.iid,s.cid as sc_id,s.seller_credit_level,if(c.num_cur=0,0,round(c.sales_cur/c.num_cur,0)) as avg_price_cur,if(c.num_cur_mon=0,0,round(c.sales_cur_mon/c.num_cur_mon,0)) as avg_price_cur_mon,if(c.num_last_mon=0,0,round(c.sales_last_mon/c.num_last_mon,0)) as avg_price_last_mon from $table c join shop s on c.sid = s.sid where c.price <> 4294967295 and c.last_trade_time<>0 and c.id > $start_id  and c.id <= ".($start_id+$limit);
		unless($is_mall) {
			$sql .= " and (c.sales_last_mon>$Limit_sales or c.sales_cur_mon>$Limit_sales) and c.num_cur_mon<=c.trade_cur_mon*$Limit_num_trade_divisor and c.num_last_mon<=c.trade_last_mon*$Limit_num_trade_divisor ";
		
		}
		$sql .= ' order by id ';
		last if $start_id >= $end_id;
		$start_id += $limit;

		my $r = {};
	
		eval{
			$r = $db->get_dbh_front()->selectall_hashref($sql,'id');
		};
		if($@) {
			solrlog("db has ERR $@");
			next;
		}
		solrlog('end select');
		#print Dumper  $r;
		print $sql,"\n" if $testlab;
		next unless %$r;
		
		my $brand_arr = [];
		my $sub_brand_arr = [];
		for my $id(keys %$r){	
			push @$brand_arr , $r->{$id}->{'brand'} ;
			push @$sub_brand_arr , $r->{$id}->{'sub_brand'} ;
		}
		my ($brand_name_ref,$sub_brand_name_ref) = @{&init_brand($brand_arr,$sub_brand_arr)};
		for my $id(keys %$r){
			my $hash = {};
			$hash->{'is_mall'} = $is_mall;
			$hash->{'last_modified'} = 'NOW';
		#	$hash->{'last_modified'} = 'NOW-3MONTHS' if $testlab;
			my $rr = $r->{$id};
			# print Dumper keys $rr;
			for my $k (keys %$rr) {
				if($k eq 'id' ) {
				
				next;
				
				}elsif ($k eq 'props'){		
					my @temp = split ';',$rr->{$k};
					$hash->{$k} = &solr_get_props(@temp);
					next;
				}elsif($k eq 'cid' or $k eq 'region' ){
					$hash->{$k.'s'} = &parents($rr->{$k},$k);
					next;
				}
				$hash->{$k} = decode_utf8($rr->{$k});
				
			}
				next if ($hash->{'avg_price_last_mon'} >= 2147483647 || $hash->{'price'} >= 2147483647 || $hash->{'avg_price_cur'} >= 2147483647 || $hash->{'avg_price_cur_mon'} >= 2147483647); 
				
				&brand_insert_into_props($hash,$brand_name_ref,$sub_brand_name_ref);
				
				push @$json1,$hash;
		}
		
		
		print '('.scalar @$json1.')';	
		solrlog('start post '.@$json1);

		my $res = $ua->post("$pre_url/update?wt=json&commit=false", Content => encode_json($json1), "Content-Type" => "application/json;");
		if(!$res->is_success){
			solrlog( Dumper $res->content);
		}
			
		solrlog('end insert');
		last if $start_id >= $end_id;
		last if $testlab;
	}

}
sub init_brand {
	my ($brand_arr,$sub_brand_arr) = @_;
	my $brand_name_ref = $db->get_dbh_front()->selectall_hashref("select name,bid from brand where bid in(".(join ',',@$brand_arr).")","bid");
	my $sub_brand_name_ref = $db->get_dbh_front()->selectall_hashref("select full_name,sbid from sub_brand where sbid in(".(join ',',@$sub_brand_arr).")","sbid");
	return [$brand_name_ref,$sub_brand_name_ref];
}

sub brand_insert_into_props{
	my ($hash,$brand_name_ref,$sub_brand_name_ref) = @_;
	if($hash->{'brand'}) {
		my $bid = $hash->{'brand'} ;
		unless($brand_name_ref->{$bid}) {
			$brand_name_ref->{$bid}->{'name'} = $db->get_dbh_front()->selectrow_array("select name from brand where bid = $bid");
		}#已经用不到了 上面全init了  不过还是留着吧
		 # else {print 'brand exit',"\n";}
		push @{$hash->{'props'}},decode_utf8($brand_name_ref->{$bid}->{'name'});
	}
	if($hash->{'sub_brand'}) {
		my $sbid = $hash->{'sub_brand'} ;
		unless($sub_brand_name_ref->{$sbid}) {
			$sub_brand_name_ref->{$sbid}->{'full_name'} = $db->get_dbh_front()->selectrow_array("select full_name from sub_brand where sbid = $sbid");
		}
		 # else {print 'sub brand exit',"\n";}
		push @{$hash->{'props'}},decode_utf8($sub_brand_name_ref->{$sbid}->{'full_name'});
	}

}
sub props_init{
	solrlog('start init props');
	my $dbh_front_main  = $db->get_dbh_front();
	$prop_ref = $dbh_front_main->selectall_hashref("select id,value_name from props where `count`>5",'id');
	solrlog('init '.(scalar keys %$prop_ref).' props');

}
sub get_time {
	my $type = shift || 0 ;
	my ($sec,$min,$hour,$mday,$mon,$year_off,$wday,$yday,$isdat) = localtime;
	if($type) {
		return sprintf("%04d-%02d-%02d",($year_off + 1900),($mon + 1),$mday);
	} else {
		return sprintf("%04d-%02d-%02d %02d:%02d:%02d",($year_off + 1900),($mon + 1),$mday,$hour,$min,$sec);
	}
}
sub solrlog {
	my $t = shift;
	my ($sec,$min,$hour,$mday,$mon,$year_off,$wday,$yday,$isdat) = localtime;
	my $today = get_time();
	print TTT  "$today\t $$ \t $t \n";

}
sub get_child_cids{
	my $parent_cids = shift;
	my $all_cid = shift;
	my $child_cids = [];
	return unless ($parent_cids and @$parent_cids);
	my $str = join ',', @$parent_cids;
	my $c = $db->get_dbh()->selectall_arrayref("select cid ,parent_cid ,name ,level from item_category_backend where parent_cid in ($str)");
	for my $t(@$c){
		push @$child_cids ,$t->[0];
	}
	if(@$child_cids){
		return &get_child_cids($child_cids, [@$all_cid, @$child_cids]);
	} else {
		return $all_cid;
	}
}

sub solr_select{
	my $res = $ua->get("$pre_url/select?wt=json&indent=true&fl=props&q=last_modified:[NOW-1DAY TO *]&rows=1");
	print Dumper $res->content;

}
sub solr_delete{
	solrlog('start solr delete');
for my $is_mall(0..1){

	my $num_remind = $ua->get("$pre_url/select?wt=json&indent=true&fl=props&q=last_modified:[NOW-1DAY TO *] is_mall:$is_mall&rows=1")->content;
	if($num_remind =~ m{"numFound":(\d+),}) {
		$num_remind = $1;
	} else {
		solrlog('delete ERR');return;
	}
	if($num_remind > ($is_mall?4000000:10000000)) {
	
	
		my $res;
		$res = $ua->get("$pre_url/update?stream.body=<delete><query>last_modified:[* TO NOW-1DAY]</query></delete>&stream.contentType=text/xml&commit=true");
		print Dumper $res->content;
		solrlog($is_mall . Dumper $res->content);
	} else {
		solrlog('dont delete');
	}
}
	solrlog('end solr delete');

}
sub solr_commit{
	solrlog('start solr commit');
	for(1..3){
		my $res = $ua->post("$pre_url/update?commit=true", "Content-Type" => "application/json;");
		if(!$res->is_success){
			solrlog( Dumper $res->content);
		} else {
			last;
		}
	}	
	solrlog('end solr commit');
}
sub solr_optimize{
	solrlog('start solr optimize');
	for(1..3){
		my $res = $ua->post("$pre_url/update?optimize=true&waitFlush=true&wt=json");
		if(!$res->is_success){
			solrlog( Dumper $res->content);
		} else {
			last;
		}
	}	
	solrlog('end solr optimize');
}

sub solr_get_props{
	my @arr = @_;
	my $return = [];
	for my $p(@arr){
	
		if($prop_ref->{$p}) {
			push @$return , decode_utf8($prop_ref->{$p}->{'value_name'}) if $prop_ref->{$p}->{'value_name'};
			#	solrlog("prop exist ");
		} else {
			my ($value_name) = $db->get_dbh_front()->selectrow_array("select value_name from props where id = $p");
		#	if($value_name){
			#	solrlog("select prop $p $value_name ");
		#	} else {
			#	solrlog("select prop $p no longer exist ");
		#	}
			push @$return , decode_utf8($value_name) if $value_name;
		}

	}
	return $return;
}
sub parents {
	my $id = shift ;
	my $type = shift ;
	&get_parents ($id,$type);
	return &order_parents($id,$type);
}
sub get_parents{
	my $id = shift ;
	my $type = shift ;

	return if $ref->{$type}->{$id} ;
	return unless $id;
#	print '-----';
	my $table = $type eq 'cid' ? 'item_category_backend' : 'region' ; 
	my $col = $type eq 'cid' ? 'parent_cid' : 'parent_id' ;
	my $o_col = $type eq 'cid' ? 'cid' : 'region_id' ;
	my $parent = $db->get_dbh_front()->selectrow_array("select $col from $table where $o_col = $id");
	$ref->{$type}->{$id} = $parent ;
	if ($parent) {	
		&get_parents ($parent,$type);
	} 
}
sub order_parents {
	my $id = shift ;
	my $type = shift ;
	my $ps = shift || [$id];
	return $ps unless $ref->{$type}->{$id} ;

	push @$ps , $ref->{$type}->{$id} ;
	&order_parents($ref->{$type}->{$id},$type,$ps);
}

sub connect(){
	my $host = shift;
	my $port = shift;
	my $user = shift;
	my $password = shift;
	my $schema = shift;

	my $dbh;
	while(1){
		eval{
			$dbh = DBI->connect("dbi:mysql:host=$host;database=$schema;port=$port", $user, $password, {RaiseError => 1, PrintError => 1});
		};
		last if($dbh and $dbh->ping());
		return undef;
		sleep 60;
	}

	$dbh->do('set names utf8');
	return $dbh;
}

sub get_content {#默认转义
	my $url = shift;
	my $conv = shift || 0;
	my $response = $ua->get($url);
	if ($response->is_success) {
		my $temp = $response->content;
		Encode::from_to($temp,'x-euc-jp','utf8') unless $conv;
		Encode::from_to($temp,'gbk','utf8') if $conv == 2;
		return $temp;
	} else {
		return $response->code.' error';
	}
	die 'has error';
}
sub dieunless1{
	my $filename = shift || $0;
	
	$filename =~ s/^.+\///;	
	my $ps_string = `ps -eo "%p,%a" |grep $filename`;
	my @list = split "\n", $ps_string;
	for(@list){
		my ($pid, $name) = split ',', $_;
		if($name =~ m{^perl|/usr/bin/perl}i){
			if ($pid != $$){
				die;
			}
		}
	}
}
