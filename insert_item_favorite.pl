#! /usr/bin/perl

use strict;
use warnings;

use Encode;
use Encode::HanConvert;
use Data::Dumper;
use Time::HiRes qw(time sleep usleep);
use FindBin qw($Bin);

use lib "$Bin/../lib";
use Utility;

my $conf = get_config();

my $url_prefix = "http://count.tbcdn.cn/counter3?_ksTS=1&callback=jsonp1&keys=ICCP_1_XXX,ICVT_7_XXX";

my $project_id = $conf->{config}->getone('conf,item_favorite,project_id');

&dieunless1();

&main();

sub main{
	$conf->{log}->sayshort("START insert");
	$conf->{db}->get_task_dbh()->do("truncate table item_favorite_url");
	
	my $iids1 = $conf->{db}->get_front_dbh()->selectall_arrayref("select m.tb_item_id, 1 from notice_shop n, shop s, mall_item m where n.sid = s.sid and s.sid = m.sid and mid = 386 ");
	my $iids2 = $conf->{db}->get_front_dbh()->selectall_arrayref("select m.tb_item_id, 0 from notice_shop n, shop s, cd_item m where n.sid = s.sid and s.sid = m.sid and mid = 386 ");
	my $iids = [@$iids1, @$iids2];

	$conf->{log}->sayshort("insert " . scalar @$iids . " iids");
		
	while(@$iids){
		my $count = 0;
		my $str = '';
		
		while(@$iids and $count < 1000){
			$count++;
			my $temp = $url_prefix;	
			my $row = shift @$iids;
			my ($iid, $is_mall) = @$row;
			my $uuid = $iid . '_' . $is_mall;
			$temp =~ s/XXX/$iid/g;
			my $url = $temp ;
			
			$str .= "('$uuid', '$url', $project_id, now()),";
		}
		
		$str = substr($str, 0, length($str) - 1);
	
		if($str){
			while(1){
				eval{
					$conf->{db}->get_task_dbh()->do("insert ignore into item_favorite_url(uuid, url, p_id, insert_time) values$str");
				};
				if($@){
					$conf->{log}->err("insert task failed", [$@]);
					sleep 60;
				}
				else{
					$conf->{log}->sayshort("insert 1000 items");
					last;
				}
			}
		}
	}		
	
	$conf->{log}->sayshort("END insert");	
}
