#! /usr/bin/perl
use strict;
use warnings;

$| = 1;

use Encode;
use Archive::Zip;
use FindBin qw($Bin);
use LWP::UserAgent;
use Date::Calc qw/Mktime Today_and_Now Today Delta_Days Add_Delta_YMD/;

use lib "$Bin/../lib";
use Log;
use DB;
use ApolloConfig;

my $conf = get_conf();
my $project_id = $conf->{config}->getone('conf,ads_tret,project_id');
my $process_num = $conf->{config}->getone('conf,ads_tret,process_num');
my $do_number_per_process = $conf->{config}->getone('conf,ads_tret,do_number_per_process');
my $curyearmonth = get_cur_yearmonth();
my $lastyearmonth = get_last_yearmonth();

#正则
my $reg_must_occur = 'Promotion.getDefaultData';
#my $reg_promo1 = '(<div id="J_ScrollingPromo".*?)<div class="extra';
#my $reg_promo2 = '(<div id="J_ScrollingPromo".*?)valItemId';
#my $reg_extra = '<div class="extra">(.*?)</div>';
#my $reg_extra_list = '(<div class="extra-list.*?)</div>';

my $curyear = get_cur_year();
my $curdate = get_cur_date();
my $curday  = get_cur_day();

my $child = {};

&dieunless1();

sub dieunless1(){
	my $filename = $0;
	
	$filename =~ s/^.+\///;	
	my $ps_string = `ps -eo "%p,%a" |grep $filename`;
	my @list = split "\n", $ps_string;
	if(@list > 4){
		$conf->{log}->err("another running : die " . scalar @list);
		die;
	}
	else{
		for(@list){
			my ($pid, $name) = split ',', $_;
			if($name =~ m{^perl}i){
				if ($pid != $$){
					$conf->{log}->err("another running : die " . scalar @list . " " . $pid);
					die;
				}
			}
		}
	}
}

&main();

sub main{
	my $nfs_dir = $conf->{config}->getone('conf,nfs_dir');
	'/var/www/spider_uploader2/htdocs/,/var/www/spider_uploader3/htdocs/,/var/www/spider_uploader4/htdocs/'
	my @nfs_dir = split ',', $nfs_dir;
	
	my @dirs = ();
	my @files = ();
	
	for my $dir(@nfs_dir){
		my @t_dirs = <$dir/$project_id/*>;
		push @dirs, @t_dirs;
	}
	
	for my $dir(@dirs){
		my @tmp_files = <$dir/*>;
		
		for my $file(@tmp_files){			
			if(-M $file > 0.01){
				push @files, $file;
			}
		}
	}
	
	while(@files){
		while(@files and (keys %$child < $process_num)){
			my @task_files;
			if(@files > $do_number_per_process){
				@task_files = @files[0..$do_number_per_process-1];
				@files = @files[$do_number_per_process..$#files];
			}
			else{
				@task_files = @files;
				@files = ();
			}
			
			if(my $pid = fork()){
				$child->{$pid} = 1;
			}
			else{	
				$conf->{log}->sayshort("fork child $$, " . join ' ', keys %$child);
				my $conf = get_conf();
				eval{
					&process_content($conf, \@task_files);
				};
				if($@){
					$conf->{log}->err("child failed $@");
				}
				$conf->{log}->sayshort("child $$ die");
				exit;
			}
			
		}
		my $pid = wait();
		delete $child->{$pid};
	}
	
	while((my $pid = wait()) != -1){}
}


sub process_content{
	my ($conf, $task_files) = @_;
	
	my $db = $conf->{db};
	my $log = $conf->{log};
	
	for my $zipfile(@$task_files){
	
		my $read_file = {};		
		my $re_hash = {};
		my $all_uuid = [];	
		
		$conf->{log}->sayshort("process zip $zipfile");
		
		# 读取zip文件的内容
		my $zip;
		my @member_files;
		eval{
			$zip = Archive::Zip->new($zipfile);
			@member_files = $zip->members();
			for my $member_file(@member_files){
				$read_file->{$member_file->fileName} = $member_file->contents;
			}
		};
		if($@){
			$conf->{log}->err("process zip $zipfile failed", [$@]);
			system "rm -rf $zipfile";;
			next;		
		}
		
		for my $file(keys %$read_file){			
			if($file =~ m{^(\d+)_(\d+)$}){
				my $s_id = $1;				
				my $tbuid = $2;
				my $Dd = 0;
				my $start_date = '';
						
				my $content = $read_file->{$file};
				
				#转码
				my $charset;
				eval{
					Encode::from_to($content, 'cp936', 'utf8');
				};
				if($@){
					$conf->{log}->err("detect charset failed! => file:$file", [$@], ['$@']);
					next;
				}
				
				unless($content =~ m{$reg_must_occur}si){
					next;
				}
				
				push @$all_uuid, $file;
				
				while($content =~ m{<li class=\\"tb-intro\\">(.*?)</li>}igs){
					$re_hash->{$s_id}->{tret} .= remove_nolink_tag($1);
					$re_hash->{$s_id}->{multiplier} = 0;
				}
				
				if($content =~ m{<li class=\\"tb-remark\\">(.*?)</li>}si){
					$re_hash->{$s_id}->{desc} = remove_all_tag($1);
					$re_hash->{$s_id}->{multiplier} = 0;
				}
				
				if($content =~ m{<span class=\\"tb-indate\\">(\d+)年(\d+)月(\d+)日}i){
					$start_date = "$1-$2-$3";
					$Dd = Delta_Days($1, $2, $3, Today());
					$Dd = 3 if ($Dd > 3);
					$re_hash->{$s_id}->{dd} = $Dd;
				}
				
				if($content =~ m{tb-next J_Next}){
					my $c = $conf->{ua}->get("http://tbskip.taobao.com/json/mjsDetail.htm?user_id=$tbuid&callback=TShop.mods.SKU.Promotion.getMjsData&page=1&mealdata=")->content;
					
					#转码
					my $charset;
					eval{
						Encode::from_to($c, 'cp936', 'utf8');
					};
					if($@){
						$conf->{log}->err("detect charset failed! => file:$file", [$@], ['$@']);
						next;
					}
					
					while($c =~ m{<li class=\\"tb-intro\\">(.*?)</li>}igs){
						$re_hash->{$s_id}->{tret} .= remove_nolink_tag($1);
						$re_hash->{$s_id}->{multiplier} = 0;
					}
					
					$conf->{log}->sayshort("$s_id : next page");
				}
				
				if($re_hash->{$s_id}->{tret}){
					my $tret = $re_hash->{$s_id}->{tret};
					my $multiplier = 0;
					my $m_num = 0;
					
					$conf->{log}->sayshort("$s_id : found tret $start_date : $re_hash->{$s_id}->{dd}");
					
					while($tret =~ m{订单满(\d+)元减(\d+)元}g){
						$multiplier += $2/$1;
						$m_num ++;
					}
					while($tret =~ m{訂單滿(\d+)元減(\d+)元}g){
						$multiplier += $2/$1;
						$m_num ++;
					}
					while($tret =~ m{订单满(\d+)元\s*?，免运费减(\d+)元}g){
						$multiplier += $2/$1;
						$m_num ++;
					}
					while($tret =~ m{訂單滿(\d+)元\s*?，免運費減(\d+)元}g){
						$multiplier += $2/$1;
						$m_num ++;
					}
					
					if($multiplier > 0){
						$re_hash->{$s_id}->{multiplier} = int($multiplier / $m_num *1000);					
					}
					
					# 另外加一下,如果tret的显示不再是以上三个了，就报警一下
					if($tret =~ m{订单满(\d+)元\s*?，免运费}){
					}
					elsif($tret =~ m{訂單滿(\d+)元\s*?，免運費}){
					}
					elsif($tret =~ m{订单满(\d+)元减}){
					}
					elsif($tret =~ m{訂單滿(\d+)元減}){
					}
					elsif($tret =~ m{订单满(\d+)元\s*?，送}){
					}
					elsif($tret =~ m{訂單滿(\d+)元\s*?，送}){
					}
					else{
						$conf->{log}->say("$s_id : WARNING", [$tret]);
					}
				}
				else{
					$conf->{log}->sayshort("$s_id : NOT found tret");
				}
			}
		}
		
		# ZIP OVER
		
		$zip = undef;		
		$conf->{log}->sayshort("process zip $zipfile over");
		
		# 插数据库
		
		$conf->{log}->sayshort("inserting ads_tret");		
		&db_process($conf, $re_hash);		
		$conf->{log}->sayshort("inserted");
		
		# update state
		
		$conf->{log}->sayshort("updating state");
		&mark_delete($conf, $all_uuid);
		$conf->{log}->sayshort("updated state");
	}
	
	# delete file
		
	$conf->{log}->sayshort("deleting file");
	my $del_str = join ' ', @$task_files;
	system "rm -rf $del_str";
	$conf->{log}->sayshort("deleted file");
}

sub db_process{
	my ($conf, $re_hash) = @_;
	
	my $sql = "insert into tret_ads_$curyearmonth(sid, `date`, tret, `desc`, multiplier) values";
	my $sql2 = "insert into tret_ads_$lastyearmonth(sid, `date`, tret, `desc`, multiplier) values";
	my $values = [];
	my $valuesLastMonth = [];
	
	for my $sid(keys %$re_hash){
		if($re_hash->{$sid}->{tret}){
			for my $dd(0..$re_hash->{$sid}->{dd}){
				$dd = 0 - $dd;
	
				if($curday+$dd>0){
					$sql .= "(?, adddate(curdate(), $dd), ?, ?, ?),";
					push @$values, ($sid, $re_hash->{$sid}->{tret}, $re_hash->{$sid}->{desc}, $re_hash->{$sid}->{multiplier});
				}else{
					$sql2 .= "(?, adddate(curdate(), $dd), ?, ?, ?),";
					push @$valuesLastMonth, ($sid, $re_hash->{$sid}->{tret}, $re_hash->{$sid}->{desc}, $re_hash->{$sid}->{multiplier});
				}
			}
		}
	}
	
	chop $sql;
	chop $sql2;
	$sql .= ' on duplicate key update tret = values(tret), `desc` = values(`desc`), multiplier = values(multiplier)';
	$sql2 .= ' on duplicate key update tret = values(tret), `desc` = values(`desc`), multiplier = values(multiplier)';
	
	if(@$values){
		eval{
			$conf->{db}->get_dbh()->do($sql, undef, @$values);
		};
		if($@){
			$conf->{log}->err("db insert ads_tret_$curyearmonth failed", [$@], ['$@']);
		}
	}
	if(@$valuesLastMonth){
		eval{
			$conf->{db}->get_dbh()->do($sql2, undef, @$valuesLastMonth);
		};
		if($@){
			$conf->{log}->err("db insert ads_tret_$lastyearmonth failed", [$@], ['$@']);
		}
	}
}

sub mark_delete{
	my $conf = shift;
	my $uuid_list = shift;
	
	return unless @$uuid_list;
	
	my $uuid_str = join ',', map {"'$_'"} @$uuid_list;
		
	# update state
	eval{
		$conf->{db}->get_task_dbh()->do("delete from ads_tret_url where uuid in ($uuid_str)");
	};
	if($@){
		$conf->{log}->err('update state failed!', [$@], ['$@']);
	}
}

sub remove_nolink_tag{
	my $str = shift;
	
	$str =~ s{<[^a/].*?>}{}gs;
	$str =~ s{</[^a].*?>}{}gs;
	$str =~ s{\s+}{ }gs;
	return $str;
}

sub remove_all_tag{
	my $str = shift;
	
	$str =~ s{<.*?>}{}gs;
	$str =~ s{\s+}{ }gs;
	return $str;
}

sub get_cur_year{
	my (undef, undef, undef, undef, undef, $year) = localtime;
	return 1900+$year;
}

sub get_cur_yearmonth{
	my ($year, $month, $day) = Add_Delta_YMD(Today(), 0, 0, 0);
	return sprintf("%04d%02d", $year, $month);
}

sub get_last_yearmonth{
	my ($year, $month, $day) = Add_Delta_YMD(Today(), 0, -1, 0);
	return sprintf("%04d%02d", $year, $month);
}

sub get_cur_date{
	my (undef, undef, undef, $day, $month, $year) = localtime;
	$year = 1900+$year;
	$month = $month + 1;
	
	return sprintf("%04d-%02d-%02d", $year, $month, $day);
}

sub get_cur_day{
	my ($year, $month, $day) = Add_Delta_YMD(Today(), 0, 0, 0);
	return $day;
}

sub get_ua{
	my $ua = LWP::UserAgent->new(
		timeout => 20,
		agent => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; zh-CN; rv:1.9.0.10) Gecko/2009042316 Firefox/3.0.10',
		cookie_jar => {},
	);
	
	return $ua;
}

sub get_conf{
	my $fn = $0;
	
	$fn =~ s/^.+\///;
	$fn =~ s/\.pl$//i;
	my $log = new Log("$Bin/../log/", $fn, 1);
	my $db = new DB();
	my $ua = &get_ua();
	my $config = new ApolloConfig();
	
	return {log => $log, db => $db, config => $config, ua => $ua};
}

1;
