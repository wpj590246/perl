#! /usr/bin/perl -w


use strict;
use warnings;

use FindBin qw($Bin);
use HTTP::Date;
use Data::Dumper;
use URI::Escape;
use Date::Calc qw/Add_Delta_DHMS Today_and_Now Add_Delta_YM/;
use DBI;


# my ($uid,$item_id);
# my $url = "http://rate.taobao.com/feedRateList.htm?userNumId=$uid&auctionNumId=$item_id&currentPageNum=2";



&main();



sub main{	
	
	my $dbh = DBI->connect('DBI:mysql:database=test;host=114.80.80.2;port:3306;','test','testA!1') or die "Can't connect";

		my	$sql = "select * from spider_weng where flag = 1 ";
		my $sql_over = "insert into spider_weng2 (item_id,uid,cur_page) values ";
	my $hash_ref = $dbh->selectall_hashref($sql,"id");
	my @array = ();
	for my $data (keys %$hash_ref)
	{
	   	my $item_id = $hash_ref->{$data}->{item_id};
	   	my $uid = $hash_ref->{$data}->{uid};
		my $cur_page = $hash_ref->{$data}->{cur_page};
		$sql_over .= "(?,?,?),(?,?,?),(?,?,?),(?,?,?),(?,?,?),(?,?,?),(?,?,?),(?,?,?),(?,?,?),(?,?,?),";
	     push @array,($item_id,$uid,$cur_page,$item_id,$uid,$cur_page+1,$item_id,$uid,$cur_page+2,$item_id,$uid,$cur_page+3,$item_id,$uid,$cur_page+4,$item_id,$uid,$cur_page+5,$item_id,$uid,$cur_page+6,$item_id,$uid,$cur_page+7,$item_id,$uid,$cur_page+8,$item_id,$uid,$cur_page+9);

    }
		if (scalar @array) {	$sql_over = substr ($sql_over,0,-1)." on duplicate key update flag = 2";	$dbh->do($sql_over,undef,@array);}	
}
