#! /usr/bin/perl
# 造词（根据搜索下拉框）
# 根据拼音抓取搜索建议中的关键词
# 约20万

use strict;
use warnings;

use FindBin qw($Bin);
use HTTP::Date;
use Data::Dumper;
use URI::Escape;
use Date::Calc qw/Add_Delta_DHMS Today_and_Now Add_Delta_YM/;
use lib "$Bin/../lib";

use Log;
use DB;
use ApolloConfig;
use Utility;

my $conf = get_config();
my $project_id = $conf->{config}->getone('conf,all_keyword,project_id');

my $url = 'http://suggest.taobao.com/sug?&extras=1&code=utf-8&callback=g_ks_suggest_callback&q=';

&dieunless1();

&main();

sub main{
	&fill_csv();
	&scp();
}

sub fill_csv{	

	my $log = $conf->{log};
	my $db = $conf->{db};
	
	$log->sayshort("START fill csv");	
	
	my $keyword1 = [' '];
	open FH, '<', "$Bin/../data/pinyin" or do{$log->err("cannot read pinyin file");die;};
	local $/;
	my $c = <FH>;
	while($c =~ m{(\w+)}gis){
		push @$keyword1, $1;
	}
	
	my $count = 0;
	
	my $rand_num = int rand 1000000;
	my $filename = time . $rand_num . '.csv';
	open FILE_O, '>', $Bin . '/../data/csv/all_keyword1/' . $filename;
	
	# 1级
	for my $word(@$keyword1){
		my $url1 = $url . $word;
		my $uuid = '1_' . $word;
		my $task_t =  [$project_id, $url1, 'GET', $uuid, '', '', ''];		
		print FILE_O join(',', @$task_t), "\n";
		
		$count++;
	}
	
	$log->sayshort("level 1 over");
	
	# 2级
	for my $word1(@$keyword1){
		for my $word2(@$keyword1){
			my $word = $word1.$word2;
			my $url1 = $url . $word;
			my $uuid = '1_' . $word;
			my $task_t =  [$project_id, $url1, 'GET', $uuid, '', '', ''];		
			print FILE_O join(',', @$task_t), "\n";
			
			$count++;
		
			if($count > 10000){
				close FILE_O;
				$log->sayshort("fill $filename with $count");		
				my $rand_num = int rand 1000000;
				$filename = time . $rand_num . '.csv';
				open FILE_O, '>', $Bin . '/../data/csv/all_keyword1/' . $filename;
				$count = 0;
			}
		}
	}
	
	$log->sayshort("level 2 over");
	
	# 3级
	#for my $word1(@$keyword1){
	#	for my $word2(@$keyword1){
	#		for my $word3(@$keyword1){
	#			my $word = $word1.$word2.$word3;
	#			my $url1 = $url . $word;
	#			my $uuid = '1_' . $word;
	#			my $task_t =  [$project_id, $url1, 'GET', $uuid, '', '', ''];		
	#			print FILE_O join(',', @$task_t), "\n";
	#			
	#			$count++;
	#		
	#			if($count > 10000){
	#				close FILE_O;
	#				$log->sayshort("fill $filename with $count");		
	#				my $rand_num = int rand 1000000;
	#				$filename = time . $rand_num . '.csv';
	#				open FILE_O, '>', $Bin . '/../data/csv/all_keyword1/' . $filename;
	#				$count = 0;
	#			}
	#		}
	#	}
	#}
	#
	#$log->sayshort("level 3 over");
	
	close FILE_O;	
	$log->sayshort("END fill csv");
}
		
sub scp{
	
	$conf->{log}->sayshort("START scp csv");
			
	opendir SOURCE, "$Bin/../data/csv/all_keyword1/";
	my @files = readdir SOURCE;
	for my $file(@files){
		if($file =~ m{\.csv$}){
			system "scp -i $Bin/../data/key/id_rsa $Bin/../data/csv/all_keyword1/$file uploader\@210.51.23.240:/var/www/spider/upload/$file.pending ";
			system "ssh -i $Bin/../data/key/id_rsa uploader\@210.51.23.240 mv /var/www/spider/upload/$file.pending /var/www/spider/upload/$file";
			if($?){
				$conf->{log}->err("SCP ERROR", [$?], ['$?']);
				redo;
			}
			else{
				system "rm -rf $Bin/../data/csv/all_keyword1/$file";
				$conf->{log}->sayshort("SCP OK => $file");
			}
			#sleep 300;
		}
	}
	closedir SOURCE;
	
	$conf->{log}->sayshort("END scp csv");
}

1;