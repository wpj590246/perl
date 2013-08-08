#! /usr/bin/perl

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
	&fill_csv();
	&scp();
}

sub fill_csv{	
	my $dbh = DBI->connect('DBI:mysql:database=test;host=114.80.80.2;port:3306;','test','testA!1') or die "Can't connect";
	my $sql = "";
while (1) {
    
	$sql = "select * from spider_weng where flag = 0 order by id limit 10000";
	
	my $hash_ref = $dbh->selectall_hashref($sql,"id");

    last unless %$hash_ref;
    my $rand_num = int rand 1000000;
    my $filename = time . $rand_num . '.csv';
    open FILE_O, '>', $Bin . '/../data/csv/' . $filename;

   
    $dbh->do("update spider_weng set flag = 1 where flag = 0 order by id limit 10000");

    for my $data (keys %$hash_ref)
	{
	   	my $item_id = $hash_ref->{$data}->{item_id};
	   	my $uid = $hash_ref->{$data}->{uid};
		my $cur_page = $hash_ref->{$data}->{cur_page};
        my $uuid = $item_id.'_'.$uid.'_'.$cur_page;
        my $url = "http://rate.taobao.com/feedRateList.htm?userNumId=$uid&auctionNumId=$item_id&currentPageNum=$cur_page";
        my $task = ['36',$url,'GET',$uuid,'','',''];
        print FILE_O join(',',@$task),"\n";
	
    }
    close FILE_O;
}
}


sub scp{
			
	opendir SOURCE, "$Bin/../data/csv/";
	my @files = readdir SOURCE;
	for my $file(@files){
		if($file =~ m{\.csv$}){
			system "scp -i $Bin/../data/key/id_rsa $Bin/../data/csv/$file uploader\@210.51.23.240:/var/www/spider/upload/$file.pending ";
			system "ssh -i $Bin/../data/key/id_rsa uploader\@210.51.23.240 mv /var/www/spider/upload/$file.pending /var/www/spider/upload/$file";
			if($?){
							redo;
			}
			else{
				system "rm -rf $Bin/../data/csv/$file";
							}
			#sleep 300;
		}
	}
	closedir SOURCE;
	
	
}