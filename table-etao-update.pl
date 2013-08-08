#! /usr/bin/perl
use strict;
use warnings;



use Encode;
use FindBin qw($Bin);
use LWP::UserAgent;
use Date::Calc qw/Today_and_Now Today Add_Delta_YM/;
use DBI;
use Data::Dumper;
use lib "$Bin/../lib";
use Utility;
use JSON;
use URI::Escape;

my $conf = get_config();
$conf->{ua} = $conf->{ua}->get_ua();
my $etao_url = 'http://s.etao.com/item/';
my $item_url = 'http://s.etao.com/product/detail_async.php?v=product&p=detail&place=b2c';
my $testlab = 0;
my $json = new JSON;
&dieunless1();
&main();

sub main{

	$conf->{log}->sayshort("START etao  task");
    my @timestemp =  Today_and_Now();
    my $sql = "select id,last_update_time from etao_item ";
    my $sql_today = sprintf("%04d-%02d-%02d", Today());
	my @item_b2c = qw(0 1 648174998 648350327 648317839 675046841 654139045 648195735 757861759);#为b2c表所对应电商在etao上的site_id
    $sql .= "where last_update_time<'".$sql_today."'"  ;
    $sql .= " limit 5000";
	
	while(1) {
        my @etao_arr = ();
		my @etao_err_arr = ();
        my $today = sprintf("%04d-%02d-%02d", Today());
        my $all_items = $conf->{db}->get_dbh_byname('phobos')->selectall_arrayref($sql);
        unless (@$all_items) {
			$conf->{log}->sayshort("no etao items update");
			last;
		}

        for my $row(@$all_items){
            my $etao_id = $row->[0];
            my $item_init_url = '';
            $etao_id='8423378' if $testlab;
            my $end_url = $etao_url.$etao_id.'.html';
		    my @item_arr = ();	
            my $content = $conf->{ua}->get($end_url)->content;
		    if($content =~ m{class=['"]\s*maintitle[^>]*?>(.*?)</h1>[\s\S]*?class=['"]img-list["']>\s*<li.*?background:url\((.*?)\)[\s\S]*?product-price-panel[\s\S]*?class=['"]price['"]>(.*?).{2}</span>}){
                my $temp = $1;#title
                $item_init_url = $2;
                #匹配etao_item表上
				eval{
					Encode::from_to($temp,'gbk','utf8');
				};
				if($@){
					$conf->{log}->err("detect charset failed! => url:$end_url", [$@], ['$@']);
					push @etao_err_arr,$etao_id;
					next;
				}
				
                push @etao_arr,$etao_id,$temp,$3*100, $2;#分别为id，title，price，img url
            } else {
                $conf->{log}->err("etao id = ".$etao_id." don't match");
				push @etao_err_arr,$etao_id;
				next;
            }
            next unless $content =~ m{id=['"]merchant['"]} ;#有无网上商店
            my $datetime = sprintf("%04d-%02d-%02d %02d:%02d:%02d",Today_and_Now());
            my $trend_hash = {};
            my $select_hash = {};
			for my $each_b2c_id(1..9) 
            {
                my $start = 0;
                my $num = 100;
                $num = 10 if $testlab;
                while (1) {
				    my $end_item_url = $item_url.'&epid='.$etao_id.'&site_id='.$item_b2c[$each_b2c_id-1].'&s='.$start.'&n='.$num;
                    $start = $start+$num;
                    print Dumper $end_item_url;
				    my $item_content = $conf->{ua}->get($end_item_url)->content;
                    last if $item_content =~ /^\s*$/ ;
                    my $item_content_json = $json->decode($item_content);
                    my @more_item =@{$item_content_json->{'moreItem'}};
                    my $final_price = $item_content_json->{'finalPrice'};
                    my @obj_data = @{($json->decode($final_price))[0]};
                    my $count = @obj_data;
					print Dumper $count;
                    for my $array_key(0..($count-1))
                    {
                        my $price = ($obj_data[$array_key]->{product_price})*100 ;
						my $name = '';
                        if ($more_item[$array_key]->{title} =~ m{class=['"]mtitle["']>\s*(.*?)\s*</h2>}) {
                            $name = $1;
                        } else {
                            $conf->{log}->err($end_item_url." don't match item title");
                        }
						eval{
							Encode::from_to($name,'gbk','utf8');
						};
						if($@){
							$conf->{log}->err("detect charset failed! => url:$end_item_url", [$@], ['$@']);
							next;
						}
                        my $b2c_id =  &get_b2c_id($obj_data[$array_key]->{link},$each_b2c_id) ; 
                        if($b2c_id eq 'error' or !$b2c_id){
                            $conf->{log}->err($obj_data[$array_key]->{link}."  don't match b2c_id");
                            next;
                        }
                        if($more_item[$array_key]->{price} =~ m{bx-data="(.*?)">}){
                            $trend_hash->{$each_b2c_id."/".$b2c_id} = $1;
                        } else {
                            $conf->{log}->err("$end_item_url  number $array_key don't match price trend");
                        }
                        push @item_arr,$each_b2c_id,$b2c_id,$name,$price,$etao_id,$datetime;
                    }
                    last if $testlab; 
                    last if $count<$num;
                }
	        }

            my $item_count = @item_arr/6;
            if($item_count) {
                $conf->{log}->sayshort("insert into item count ".$item_count);
                # print Dumper @item_arr;return;
                my $insert_item = "insert  into item(b2c,b2c_id,name,price,img,etao_id,create_time) values "."(?,?,?,?,'$item_init_url',?,?),"x($item_count-1)."(?,?,?,?,'$item_init_url',?,?) on duplicate key update name=values(name),price=values(price)";

				eval {
					$conf->{db}->get_dbh_byname('phobos')->do($insert_item,undef,@item_arr);
					$conf->{log}->sayshort("these items insert or update : @item_arr");
				};
				if($@) {
					$conf->{log}->err("insert into item failed :$@");
				}
                $conf->{log}->sayshort("end insert into item");
            }

            #select ids what just inserted 
            if(%$trend_hash){
                my $select_sql = 'select id,b2c,b2c_id from item where ';
                my @where_arr = ();
                for my $combine(keys %$trend_hash) {
                   my @temp = split(/\//,$combine);
                   push @where_arr , " (b2c=".$temp[0]." and b2c_id='".$temp[1]."') ";
                }
                $select_sql .= join('or',@where_arr);
                my $select_items = $conf->{db}->get_dbh_byname('phobos')->selectall_arrayref($select_sql);
                for my $select_row(@$select_items) {
                    $select_hash->{$select_row->[1]."/".$select_row->[2]} = $select_row->[0];
                
                }
            }

            #price trend data 
            if(%$select_hash) {
                my $min_data = sprintf("%04d-%02d-%02d",Add_Delta_YM(Today(),'0','-3'));
                my $insert_trend = {};
                for my $hash_key (keys %$trend_hash) {
                    my $id = $select_hash->{$hash_key};
					unless($id) {
						$conf->{log}->err("table item don't has $hash_key");
						next;
					}
                    $trend_hash->{$hash_key} =~ s/'/"/g;
                    my @trend_data = @{$json->decode( $trend_hash->{$hash_key})};
                    for my $trend_row(@trend_data){
                        my $format = sprintf("%04d-%02d-%02d",split('-',$trend_row->[0]));
                        if($format gt $min_data) {
                            push @{$insert_trend->{&Utility::get_yyyymm($format)}},$id,$format,$trend_row->[1]*100;
                        }
                    }
                }

                if(%$insert_trend) {
                    for my $trend_date(keys %$insert_trend){
                        my $trend_count = @{$insert_trend->{$trend_date}}/3;
                        my $sql_trend = "insert ignore into item_price_trend_".$trend_date." values "."(?,?,?),"x($trend_count-1)."(?,?,?)";
						eval {
							$conf->{db}->get_dbh_byname('phobos')->do($sql_trend,undef,@{$insert_trend->{$trend_date}} );
							$conf->{log}->sayshort("these price trend insert or ignore : @{$insert_trend->{$trend_date}}");
						};
						if($@) {
							$conf->{log}->err("insert into item_price_trend_".$trend_date." failed :$@");
						}
                    }
                }
            }
            return if $testlab; 
        }
        my $etao_count = @etao_arr/4;
        if($etao_count) {
            $conf->{log}->sayshort("update etao_item count ".$etao_count);
            my $insert_etao = "insert into etao_item(id,name,price,img) values "."(?,?,?,?),"x($etao_count-1)."(?,?,?,?) on duplicate key update name=values(name),price=values(price),img=values(img),last_update_time='".$today."'";
            eval{
				$conf->{db}->get_dbh_byname('phobos')->do($insert_etao,undef,@etao_arr);
				$conf->{log}->sayshort("these etao items  update : @etao_arr");
            };
			if($@) {
				$conf->{log}->err("update  etao_item failed $@");
			}
			$conf->{log}->sayshort("end update etao_item");
        }
		#发生错误的 etao item 更新
		if (@etao_err_arr) {
			my $update_etao_err = "update etao_item set last_update_time='".$today."' where "."id=? or "x(@etao_err_arr-1)." id=?";
            
			eval{
				$conf->{db}->get_dbh_byname('phobos')->do($update_etao_err,undef,@etao_err_arr);
				$conf->{log}->sayshort("these error etao items   update : @etao_err_arr");
            };
			if($@) {
				$conf->{log}->err("update error  etao item failed $@");
			}
			
		}
    }
    $conf->{log}->sayshort("END etao  task");
}
sub get_b2c_id{
    my ($link,$b2c)=@_;
    if($b2c== 1 or $b2c==2) {
		return $1 if $link =~ m{(\d*)}; 
    } 
    elsif ($b2c == 3) {
		return $1 if $link =~ m{item\.jd\.com/(\d*)\.html};
    }
    elsif ($b2c==4){
        return $1 if $link =~ m{product_id=(\d*)};
    } 
    elsif ($b2c==5){
        return $1 if $link =~ m{emall/(.*?)\.html};
    } 
    elsif ($b2c==6){
        return $1 if $link =~ m{/dp/(.*?)/?$};
    }
    elsif ($b2c==7){
        return $1.'-'.$2 if $link =~ m{productId=(\d*).*?&skuId=(\d*)};
		return $1 if $link =~ m{productId=(\d*)};
        return $1 if $link =~ m{product/(.*?)\.html};
    } 
    elsif ($b2c==8){
        return $1 if $link =~ m{item/(\d*_\d{1,2})};
    } 
    elsif ($b2c==9){
        return $1 if $link =~ m{item-(\d*)\.html};
    }
    return 'error';
}
