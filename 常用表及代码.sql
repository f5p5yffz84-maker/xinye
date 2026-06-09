--建表
/*
drop table if exists test.draft_066836_260525;
create table test.draft_066836_260525 stored as parquet as
;
*/

-- 常用表
select * from ddm.cs_dunning_case_owner_rt
where allot_module_name = '云金_易投诉_1-90'
and to_date(allot_time)=to_date(now()); --未出催案件宽表（每小时更新），常用字段：allot_module_name
select * from edw.d_cs_dun_case; -- 7点v2表切片表
select * from edw.d_cs_dun_case_snp;-- 7点v2表切片表snp表，分区dt和is_close
select * from edw.d_cs_dun_case_zero_time_snp;--24点切片表
select * from edw.tb_dun_case_snp;--0点切片表，所在模块会延迟一天，因为凌晨还未分案
select * from edw.d_cs_assets_company_info
order by id desc;-- 资产信息
select * from cszc.fmj_ins_type_dl_info;--cps信息表
select * from edw.dim_kf_owner_snp; --客服坐席信息表
select * from edw.dim_cs_owner_all_snp
where is_disable = 0; --经办信息表
select * from ddm.fact_user_cs_phone_recommend;--主营人工号码推荐
select * from ddm.cs_user_phone_recommend_dl_dly;--导流人工号码推荐
select * from ddm.cs_owner_in_charge_of_case_snp;-- 经办在库表

select * from cszc.fs_wb_hk_clear_total;-- 法诉还款表
select * from cszc.wb_hk_total_datail_clear;--电催还款表

-- 绩效报表算mtd回款
select user_id,
       dun_case_id,
       substr(allot_time_simple, 1, 7)                    as month,
       min(allot_time_simple)                             as min_allot_time,
       SUM(case when rn = 1 then startowingamount_kc end) as start_owing_amount,
       SUM(dun_repay_amount)                              as dun_repay_amount
from (select *
           , row_number() over (partition by model_dc,dun_case_id,product_id,period_id order by allot_time) as rn
      from cszc.mrjx_dp_stats) a  --cszc.dl_mrjx_dp_stats
group by 1, 2, 3
;

-- 整个模块/经办维度mtd回款
select model_dc,owner_id,owner_name,start_case_cnt,dun_repay_amount,start_owing_amount,mth
from cszc.sjzn_mrjx_mtd
where data_level='5.经办层级'
and mth>='2025-07'
and is_new_date=1
and model_dc in ('CL_API_1-30','CL_API_M2','CL_API_M3')
;

-- 模块规则
with t1 as (
    select id as rule_id,module_id,module_name
    from edw.ppdai_ddcas_tb_assist_allot_rule_snp
    where dt=to_date(now())
      and status=1      --规则启用状态
      and system_type='assets_dun'  -- 智借系统
)
-- 模块规则对应协催小组
,t2 as (
    select rule_id,company_id,company_name,group_id as assist_display_group_id,group_name as assist_display_group_name
    from edw.ppdai_ddcas_tb_assist_allot_rule_detail_snp
    where dt=to_date(now())
    and status=1        -- 有效小组
)
   -- 协催小组内对应分案人员
,t3 as (
    select assist_display_group_id,user_id
    from edw.ppdai_dds_tb_group_assist_user_snp
    where  dt=to_date(now())
    and isactive=1            -- 有效数据
    and assist_handle=1
)

select t1.*
,t2.company_id,company_name,t2.assist_display_group_id,assist_display_group_name
,t3.user_id
,to_date(now()) as dt
from t1
join t2 on t1.rule_id=t2.rule_id
join t3 on t2.assist_display_group_id=t3.assist_display_group_id
;

--根据外部文件建表
/*
drop table if exists test.066836_0625_temp;
create external table test.066836_0625_temp
(
dt string,
case_cnt int
)row format delimited fields terminated by ',' stored as textfile location '/external/user/zhongyue/临时'
;
*/
-- 复制表
/*
create table table_new like table_old;
insert overwrite table table_new partition(dt)
select * from table_old;
*/

--案件实时查询
/*
ods.tb_dun_case_v2
ddm_cs.d_cs_tb_dun_case_v2      --主营
ddm_dlcs.d_cs_tb_dun_case_v2    --导流
常用字段：
user_id,own_id
*/

--逾期标的用户机构名查询
/*
select a.listing_id
     , a.user_id
     , a.invest_listing_id
     , b.institutionid
     , c.ins_name
     , count(1)
from edw.list_loan_total_snp a
         left join
     (select listing_id, user_id, invest_listing_id, institutionid
      from edw.cmn_listing
      group by 1, 2, 3, 4) b
     on a.listing_id = b.listing_id and a.user_id = b.user_id and a.invest_listing_id = b.invest_listing_id
         left join edw.dim_institution_financing_info c on b.institutionid = c.ins_id
where a.dt = to_date(now())
  and a.current_default_days > 0

*/


--比较两个表的数据差异
/*
select count(*) from cszc.maxine_useless_no_unvalid_tag_066836
union
select count(*) from cszc.maxine_useless_no_unvalid_tag
;
select key from (
select * from cszc.maxine_useless_no_unvalid_tag_066836
union all
select * from cszc.maxine_useless_no_unvalid_tag
)a
group by key
having count(*) <> 2
;

*/

--经办信息查询
/*
表：
describe ods.tb_group_user               --催收经办表
;
select * from ods.tb_dun_group                --模块组别表
where group_id in (323,328,338,29,386,28,31,16,30,33,118,17,32,396)
;
describe ods.tb_dun_display_group        --催收组别表
describe ods.dim_third_dun_case_company  --公司信息表
select * from edw.dim_cs_owner_all_snp --经办切片表

常用字段：
user_id,group_id,group_name
*/

--案件信息+经办+模块信息
/*
select
    a.*
    ,c.group_id
    ,c.group_name
    ,d.company_name
    ,d.company_type
from (
    select *
    from ods.tb_dun_case_v2
    where isactive
    and dun_close_reason_id = 0
    ) a
left join ods.tb_group_user b
on a.own_id = b.user_id
left join (select * from ods.tb_dun_group
    where group_id
    in (35,65,120,330,383,426)
) c
on b.group_id = c.group_id
left join ods.dim_third_dun_case_company d
on a.company_id = d.company_id
;
--经办
select *
from ods.tb_group_user
where user_id in (10030009)
real_name = '李银银'
;

*/

select * from ods.tb_group_user b
left join ods.tb_dun_group c
on b.group_id = c.group_id
and b.group_id = 400
and b.isactive
and b.is_allot
where b.display_group_id = 3723
;
--分案信息

describe ods.tb_pending_case                   --待分案
;
describe edw.d_cs_case_dddrools_preselect      --预选
;
describe edw.d_cs_case_dddrools_mark           --标记
;
describe edw.d_cs_case_allocation              --分案表，timemark
;
describe edw.d_cs_case_allocation_dly          --分案表 限制：where admin_id = 1564362--系统 and record_type = 1，准实时，无逾期金额
;
describe edw.b_cs_case_allocation_dly          --分案表，有逾期金额，基于上面d表加工
;
describe ods.tb_case_allocation_detail         --分案明细表，与分案表的差距在于，少了更新时已出催的案件
;
describe edw.d_cs_case_dddrools_company_allot  --公司分案表
;
describe edw.d_cs_case_dddrools_group_allot    --小组分案表
;
describe ods.rt_tb_dun_case_detail             -- 准实时标的粒度信息表
;

describe ddm.s_cs_case_final_allocation_dly
;
--协催分案记录表

describe ods.ppdai_ddcas_tb_case_assist_allot  --协催分案表（t+1）
;
describe ods.rt_ppdai_ddcas_tb_case_assist_allot --协催分案表（准实时）
;
describe ods.ppdai_ddcas_tb_case_assist_allot_detail --协催分案明细表（t+1）
;
describe ods.ppdai_ddcas_tb_case_assist_pre_allot  --协催案件预选表
;
describe  edw.o_tb_case_assist_allot--实时分案表，status状态 1:已分配 2:已回收 3:已出催；isactive逻辑删除(1:保留,0:删除)
;
describe edw.o_tb_case_assist_allot_detail  --每日"Owner分案"最后一条分案记录及案件最新状态表
;
describe cszc.assist_allot_case_base_zy --每日协催推案
;
select count(*) from cszc.assist_allot_case_base_zy where dt= to_date(now()) and module_id=120;

--check协催分案
select module_id,count(1) from ods.rt_ppdai_ddcas_tb_case_assist_allot
where to_date(allot_time) >= '2026-04-01'
  and module_id in (489,599,591)
--   and to_date(allot_time) not in ('2025-01-28','2025-05-01')
-- and owner_id = 20051031
-- and user_id = 300044059
group by 1
;
select * from ods.tb_dun_case_v2 where user_name='pdu0848632642';

select * from ods.rt_ppdai_ddcas_tb_case_assist_allot
where to_date(allot_time) = '2025-06-26'
and user_id=120577193
;


select module_id,status,count(*)
from ods.ppdai_ddcas_tb_case_assist_allot
where isactive=1 and to_date(allot_time) >= '2024-01-01' group by 1,2;
--已推送但未协催分案
select a.module_id,
       a.model_name,
       a.dun_case_id,
       a.user_name,
       a.user_id,
       a.owing_amount,
       a.max_default_days,
       a.company_id,
       b.user_name as owner_name,
       case when d.dun_case_id is not null then 1
           else 0 end as is_allot,
       d.operate_id,
       d.allot_time,
       d.status
from (
    select count(*)
    from cszc.assist_allot_case_base_zy
    where dt = to_date(now())
    and module_id = 35
--     and max_default_days between 4 and 15
--     and owing_amount between 0 and 2000
    ) a
left join (
    select *
    from ods.rt_ppdai_ddcas_tb_case_assist_allot
    where to_date(allot_time) = to_date(now())
    and isactive = 1
    ) d  --status状态 1:已分配 2:已回收 3:已出催
on a.dun_case_id = d.dun_case_id
left join ods.tb_group_user b
on d.owner_id = b.user_id
;
--当日协催推送案件
select model_name,count(*)
from cszc.assist_allot_case_base_zy
where dt = to_date(now())
and module_id = 120
group by 1
;

-- 人力计划
show table stats cszc.066836_2301_rljh_monthlyadd;
-- 查覆盖率
select module_name,mth
     ,total/man_needed as fgl
,man_needed
,total
    from cszc.066836_2301_rljh_monthlyadd
where
 module_name rlike '拍小租'
and mth >= '2024-12'
order by 1,2
;

select * from cszc.066836_2301_rljh_monthlyadd where mth='2025-12';
--线下表上传
drop table if exists cszc.066836_0930;
create external table cszc.066836_0930
(
user_id bigint
)row format delimited fields terminated by ',' stored as textfile location '/external/user/zhongyue/临时';
select * from cszc.066836_0930;

--建分区表
drop table if exists cszc.m0_asp_public_case_tot;
create table cszc.m0_asp_public_case_tot
(
module_id int
,model_name string
,yuan_owner_id bigint
,dun_case_id bigint
,user_name string
,user_id bigint
,owing_amount double
,max_default_days int
,assets_id bigint
,company_id bigint
,system_type string
)
partitioned by (dt string,allot_tag string) stored as parquet;

insert overwrite table cszc.cjtc_zy partition (dt = to_date(now()));
insert overwrite table cszc.cjtc_zy partition (dt);

--带注释分区表
drop table if exists cszc.066836_tmp_dly;
create table cszc.066836_tmp_dly
(
user_id bigint,
strategy_category string COMMENT '差异化策略一级分类',
strategy_class string COMMENT '差异化策略二级分类',
self_ph_rec int COMMENT '本人号码推荐上限',
nself_ph_rec int COMMENT '三方号码推荐上限',
ph_rec int COMMENT '号码推荐上限',
user_type_change string COMMENT '改动模块',
dw_cre_date string,
dw_upd_date string
)
partitioned by (dt string) stored as parquet;

--改表名
alter table table_a rename to table_b;
--改表的字段
alter table <表名> change <字段名> <字段新名称> <字段的类型>;
alter table cszc.066836_cs_all_category_list_anliang change user_id user_cnt bigint;
--筛选标记但未分案的案件，原本用v2表检查会受到手动分案的影响，因此换成分案表，便于事后查询
drop table if exists test.fenan_list_0401_zy;
create table if not exists test.fenan_list_0401_zy stored as parquet as
with
t0 as
    (
    select *
    from edw.d_cs_case_dddrools_mark
    where to_date(inserttime) > '2024-03-31 20:00:00'
    and to_date(inserttime) < '2024-04-01 8:00:00'
    ),
t1 as
    (
    select *
    from edw.d_cs_case_allocation_dly
    where admin_id = 1564362  --系统
    and record_type = 1       --分案
    and dt = '2024-04-01'
    ),
t2 as
    (select t0.*
    from t0
    left anti join t1
    on t0.dun_case_id = t1.dun_case_id
    join (
        select dun_case_id from ods.tb_dun_case_v2 where isactive and dun_close_reason_id = 0
    ) a
    on t0.dun_case_id = a.dun_case_id
    )
select * from t2
;
--check数量
select group_id,count(*) from test.fenan_list_0401_zy
group by 1
;
--随机分案
drop table if exists cszc.90_fenan_0401_zy;
create table if not exists cszc.90_fenan_0401_zy stored as parquet as
with
t0 as
    (
    select
        *,
        row_number() over (order by rand()) as rank
    from test.fenan_list_0401_zy
    )
select
    *,
    case when rank <= 99128 then 'cx5s'  --根据实际分案需求更改
    when rank <=  141610  then 'hs5s'
    when rank <=  163839  then 'maiquan5s'
    when rank <=  167303  then 'penghao5s'
    else 'rongzhibo5s' end as owner_id
from t0
;
--检查分配是否均匀
select
    owner_id
    ,avg(user_owing_amount)
    ,avg(user_max_default_days)
    ,count(*)
from cszc.90_fenan_0401_zy
group by 1
;
--插入批量修改owner接口
insert into cszc.plxg_owner_lm
select
    to_date(now()) as day
    ,user_id as userId
    ,ower_id as ownerUserName
    ,20039089 as operateUserId
    ,1 as record_type
from  cszc.90_fenan_0401_zy
;
--检查插入成功
select count(*) from cszc.plxg_owner_lm where day = to_date(now())
;

--具有重复column_name值的数据以及它们的重复次数
SELECT * FROM t0
WHERE column_name IN
(
SELECT column_name
FROM t0
GROUP BY 1
HAVING COUNT(*) > 1
)
order by column_name
;

--返回在a表中存在但在b表中不存在的所有行
select a.*
from a
left join b on a.字段 = b.字段
where b.字段 is null
;

--impala查询具体sql语句执行者以及执行时间
select *
from ods.impala_query_summary
where
    batch_date >='2026-01-06' and
 sql_statement like '%cszc.draft_066836_260106_jx_complaint%'
limit 100
;

--催收系统号码推荐
select * from ddm.fact_user_cs_phone_recommend
where dt ='2025-07-28'
--   and (phone rlike '0706')
and user_id = 101743358
;


--asp号码推荐
select * from ddm.cs_user_phone_recommend_asp_dly
where dt >='2025-06-28'
--   and (phone rlike '1775')
and user_id = 129439443
;

--大数据
select
      *
from tmp.cs_phone_all_user_tag
where user_id =1750001160
and dt = to_date(adddate(now(),-1))
;

-- 大数据上游表
select * from edw.fact_user_cs_phone_rule
where user_id =187715373
and dt = to_date(adddate(now(),-1))
;


-- 停催号码
select distinct mobile_phone as phone
                    ,1 as is_del
                    ,'is_stop_cs' as del_type
      from ods_s.ppdai_dds_tb_dun_phone_stop
      where substr(end_time,1,10)>=to_date(date_add('${BATCH_DATE}',1))
        and substr(begin_time,1,10)<to_date(date_add('${BATCH_DATE}',1))
        and type regexp '^1,|^1$|,1,|,1$|,3,|^3,|,3$|^3$'	 --停催类型 1:号码停止拨打 2：停发催收短信；3：同时停催电话以及短信(不会有增量) 4:停催微信  20240530研发变更记法  "1" "1,2" "2,3,4"
        and route in ('manual','all')  --manual 人工 tieniu 铁牛 all 所有
        and isactive=1  --客服同学对某个手机号进行解封操作时，表里的isactive就会变为0
        and mobile_phone in (
'13280516159'
          )
;
-- 用户停催
select *
             from ods.ppdai_dds_tb_dun_people_stop
            where isactive=1
              and substr(end_time,1,10) >= to_date(date_add(${BATCH_DATE},1))  -- 加一天的原因是号码推荐结果数据是第二天才用
              and substr(begin_time,1,10)< to_date(date_add(${BATCH_DATE},1))
              and type regexp '^1,|^1$|,1,|,1$|,3,|^3,|,3$|^3$'	 -- 停催类型 1号码停止拨打 2停发催收短信 3同时停催电话以及短信(不会有增量) 4:停催微信    20240530研发变更记法  "1" "1,2" "2,3,4"
              and route in ('manual','all')  -- manual 人工 tieniu 铁牛 all 所有
and user_id in (77422461)
;
-- 停催号码解封
select distinct mobile_phone as phone
                    ,1 as is_del
                    ,'is_stop_reopen' as del_type
      from ods_s.ppdai_dds_autosync_2_tb_dun_people_stop_reopen  --停催解封
      where isactive=1
;


select * from ods.tb_dun_case_v2 where user_id = 153235274 and dun_close_reason_id = 0;
--asp号码推荐
select
      *
from cszc.cs_user_phone_recommend_asp_tmp
where
--     user_id = 1905883138
--   and (phone rlike '1309' or phone rlike '2006')
dt >= '2025-05-02'
and phone = '15715931997'
-- and dt = to_date(adddate(now(),-1))
;
--号码推荐
select
      *
from cszc.fact_user_cs_phone_recommend_tmp
where dt > '2025-05-01'
and user_id =172365680
and phone ='15908650876'
and phone ='15908650876'
;
--客服新增号码
select *
from ods_s.tb_dun_user_mobile
where mobile like '%4171'
and user_id = 1810363824
;
--策略分客群
select
      *
from cszc.cs_user_number_of_rec_phone_strategy_dly
where user_id = 125227922
-- and phone like '%4433'
and dt >= '2024-08-09'
;
-- 用户可推荐号码
select * from cszc.066836_user_phone_available_snp
where user_id = 81774348
  and phone ='13280516159'
and dt >='2025-07-15'
order by dt
;
--第一层过滤
select * from cszc.cs_phone_all_user_tag_filter_tmp_asp
where user_id = 140465574;
--指掌易、客服流程需求、二次放号剔除
select total.phone
     , total.user_id
     , case when zzy.phone is not null then 1 else 0 end as '是否指掌易停催'
     , case when kf.phone is not null then 1 else 0 end as '是否客服停催'
     , case when ecfh.phone is not null then 1 else 0 end as '是否二次放号停催'
from cszc.fmj_zzy_hm_esl_asp total
         left join (select phone
                    from edw.dim_cs_bind_phone_zzy_chn
                    where is_valid = 1
                      and end_dt > now()
                    group by 1) zzy
                   on total.phone = zzy.phone
         left join (select mobile_phone                                                                             as phone,
                           cast(regexp_extract(reason, '(因解绑号码而操作号码停催7天-用户ID：)+(.*?)', 2) as bigint) as user_id
                    from ods_s.ppdai_dds_tb_dun_phone_stop
                    where reason rlike '因解绑号码而操作号码停催7天'
                      and isactive = 1
                    union
                    select phone, user_id
                    from cszc.fmj_kf_phone_delete_tot) kf
                   on total.phone = kf.phone
                       and total.user_id = kf.user_id
         left join (select phone
                    from cszc.fmj_ecfh_tc_list_tot
                    group by 1) ecfh
                   on total.phone = ecfh.phone
where total.phone = '15640735888'
;
-- 指掌易
select * from edw.dim_cs_bind_phone_zzy_chn
where phone ='15640735888'
and is_valid=1
and end_dt > now()
;
--流程需求剔除
select
      *
from cszc.fmj_kf_phone_delete_tot
where phone in (
'15640735888'
)
;

select mobile_phone                                                                             as phone,
       cast(regexp_extract(reason, '(因解绑号码而操作号码停催7天-用户ID：)+(.*?)', 2) as bigint) as user_id,
       cast(0 as double)                                                                        as order_id
from ods_s.ppdai_dds_tb_dun_phone_stop
where reason rlike '因解绑号码而操作号码停催7天'
  and isactive = 1
and mobile_phone in ('15640735888')
;
--二次放号剔除
select
      *
from cszc.fmj_ecfh_tc_list_tot
where phone in (
'15640735888'
)
;
-- 发送表
describe ods.smsmessage_2018;
select *
from ods.smsmessage_2018
where templateid = 5627
;

-- 模板匹配表
describe ods.aimessage;
select * from ods.aimessage where aitemplatealias rlike '2691';


-- 短信黑名单库（用户退订的黑名单）
describe ods.blacklist;


-- 用户回复短信
describe ods.smsmessagemorecord;


-- 部门表
describe ods.department;

-- 模板匹配表
describe ods.messagetemplate;
select * from ods.messagetemplate
where templatealias rlike 'tpl_br-M0jhsy8-cldlAPI_7068';

-- 汇总
select a.recipient,
       a.content,
       a.templateid,
       a.contenttype,
       case
           when a.contenttype = 1 then '验证码消息'
           when a.contenttype = 2 then '普通消息'
           else '其他' end as contenttype_name,
       a.status,
       case
           when a.status = -1 then '提交失败'
           when a.status = -2 then '发送失败'
           when a.status = -3 then '黑名单拦截'
           when a.status = 0 then '初始化'
           when a.status = 1 then '发送中'
           when a.status = 2 then '提交成功'
           when a.status = 3 then '发送成功'
           else '其他' end as status_name,
       a.aimessageid,-- AiMessageId,可用于区分是否是ai消息
       a.isactive          as send_isactive,
       a.inserttime,
       a.updatetime,
       a.tenementid,
       a.par_dt,
       b.isactive          as template_isactive,
       b.messagekind,
       case
           when b.messagekind = 1 then '验证码'
           when b.messagekind = 2 then '通知'
           when b.messagekind = 3 then '营销'
           when b.messagekind = 4 then '催收'
           else '其他' end as messagekind_name,
       b.templatename,
       b.templatealias,
       b.intervaltime, -- 间隔时间
       b.maxcount, -- 最大发送次数
       b.totalmaxcount, -- 一天总体发送次数
       c.departmentname
from (select * from ods.smsmessage_2018 where par_dt >= '2024-10') a
         left join ods.messagetemplate b
                   on a.templateid = b.templateid
         left join ods.department c
                   on b.departmentid = c.departmentid
where b.isactive = 1 -- 限制在用
--   and b.templatealias = 'tpl_【PPD】1-3t_6141'  -- templateid = 7717
  and b.templatealias = 'tpl_sx_4647' -- 限制模板  templateid = 5627
;

-- 催收短信表
select * from edw.b_cs_msg_dly;




/*
主营：edw_s.dim_user_info_daily
非主营：edw_s.common_tenant_user_daily
--全公司用户三要素表
(不含工作单位)
edw_s.common_tenant_user 非快照表

真实姓名+工作单位，没有合在一起的表
--主营用户
select cmstr_real_name, cmstr_comp
from edw_s.dim_user_info_daily
where dt='2021-12-23'
;
--所有多租户的，不包含主营
select cmstr_real_name,cmstr_co_name
from edw_s.common_tenant_user_daily
where dt='2021-12-23';--限制tenant name='KO0分期' 表示KOO
*/

--学习代码
/*
1.regexp_extract()函数
语法: regexp_extract(string subject, string pattern, int index)
返回值: string
说明：将字符串subject按照pattern正则表达式的规则拆分，返回index指定的字符
idx是返回结果 取表达式的哪一部分 默认值为1。
0表示把整个正则表达式对应的结果全部返回
1表示返回正则表达式中第一个() 对应的结果 以此类推。
例：
select regexp_extract('{"dunCaseId":88999705,".', '({"dunCaseId":)+(.*?)+(,")+(.*?)', 2) as dun_case_id;--加号可省略
原文链接：https://blog.csdn.net/weixin_43597208/article/details/123860020

2.COALESCE(expression_1, expression_2, ...,expression_n)函数
依次参考各参数表达式，遇到非null值即停止并返回该值。如果所有的表达式都是空值，最终将返回一个空值。
使用COALESCE在于大部分包含空值的表达式最终将返回空值。
原文链接：https://blog.csdn.net/yilulvxing/article/details/86595725

3.default.get_hashed_isin("M0_1_6_cs_phone_rec",cast(t.user_id as string),0.000,0.300)哈希函数
default.get_hashed_isin()函数

4.exists()函数
SELECT column1 FROM t1 WHERE [conditions] and EXISTS (SELECT * FROM t2 );
括号中的子查询并不会返回具体的查询到的数据，只是会返回true或者false，如果外层sql的字段在子查询中存在则返回true，不存在则返回false
即使子查询的查询结果是null，只要是对应的字段是存在的，子查询中则返回true
执行过程
1、首先进行外层查询，在表t1中查询满足条件的column1
2、接下来进行内层查询，将满足条件的column1带入内层的表t2中进行查询，
3、如果内层的表t2满足查询条件，则返回true，该条数据保留
4、如果内层的表t2不满足查询条件，则返回false，则删除该条数据
5、最终将外层的所有满足条件的数据进行返回
外层小表，内层大表（或者将sql从左到由来看：左面小表，右边大表）： exists 比 in 的效率高
外层大表，内层小表（或者将sql从左到由来看：左面大表，右边小表）： in 比 exists 的效率高

5.left()，right()函数

6.regexp()和rlike()类似
这个正则表达式 `^2,|^2$|,2,|,2$|,3,|^3,|,3$|^3$` 是用来匹配包含数字2或3的字符串的模式。下面对每个部分进行详细解释：

1. `^2,`：以数字2开头并且后面紧跟逗号的部分。例如，匹配字符串 "2,apple" 中的 "2,"。
2. `|^2$`：以数字2开头并且只包含数字2的部分。例如，匹配字符串 "2"。
3. `,2,`：逗号包围的数字2的部分。例如，匹配字符串 "apple,2,orange" 中的 ",2,"。
4. `,2$`：以数字2结尾并且前面紧跟逗号的部分。例如，匹配字符串 "apple,2" 中的 ",2"。
5. `,3,`：逗号包围的数字3的部分。例如，匹配字符串 "apple,3,orange" 中的 ",3,"。
6. `|^3,`：以数字3开头并且后面紧跟逗号的部分。例如，匹配字符串 "3,apple" 中的 "3,"。
7. `,3$`：以数字3结尾并且前面紧跟逗号的部分。例如，匹配字符串 "apple,3" 中的 ",3"。
8. `|^3$`：只包含数字3的部分。例如，匹配字符串 "3"。

这个正则表达式的目的是匹配包含数字2或3的字符串，无论其在字符串中的位置如何。

7.窗口函数：
count(*)/sum(*)/row_number(*) over(partition by order by )
算百分比,占比：round(count(*)/sum(count(*)) over(),2)
算累计：sum(count(distinct user_id)) over (partition by month order by day) as cumulative_users
按某分区计数：sum(count(1)) over (partition by dt,max_default_days) as total_case_cnt

8.substr()函数格式 (俗称：字符截取函数)
格式1： substr(string string, int a, int b);
格式2：substr(string string, int a) ;

格式1：
    1、string 需要截取的字符串
    2、a 截取字符串的开始位置（注：当a等于0或1时，都是从第一位开始截取）
    3、b 要截取的字符串的长度
格式2：
    1、string 需要截取的字符串
    2、a 可以理解为从第a个字符开始截取后面所有的字符串。

9.if(判断条件,满足条件取值,不满足条件取值)

10.split_part(string,"截取符",字段位置)

11.批量删除分区数据
alter table cszc.cs_user_phone_recommend_asp_tmp drop partition(dt < '2024-12-01');
alter table cszc.cs_user_phone_recommend_asp_tmp drop partition(dt < to_date(add_months(now(),-3)));-- 仅保留近3个月数据

12.concat()(拼接函数)
CONCAT(string1,string2, ... );
CONCAT()函数在连接之前将所有参数转换为字符串类型。如果任何参数为NULL,则CONCAT()函数返回NULL值。

13.使用lateral view explode函数将一个包含指定分隔值的字符串列表拆分成多行
lateral view explode(split(字段1, '分隔值')) mytable1 as tag1
lateral view explode(split(字段2, '分隔值')) mytable2 as tag2

14.GROUP_CONCAT([DISTINCT] 要连接的字段 [Order BY ASC/DESC 排序字段] [Separator ‘分隔符’])
将同一个分组下的行拼接在一起，默认逗号
group_concat(distinct phone, ',') as phone ，不能排序


15.去重
distinct，group by
group by 效率更高
多指标去重：先打标签，再统计

16.聚合函数替代窗口函数求最值
select
    user_id
    ,substr(max(concat(deal_time,deal_amount)),20) as deal_amt--deal_time有19位，从第20位开始
    ,max(deal_time) as deal_time
from edw.dwd_cmn_listing
group by user_id
;

17.表增加/删除字段
ALTER TABLE cszc.phone_reduce_case_2408_dly ADD COLUMNS (self_phone_cnt bigint comment '' ,other_phone_cnt bigint)
ALTER TABLE 表名 DROP 字段名 -- 一次只能删除一个字段


18.删除数据
insert overwrite table cszc.plxg_owner_lm
select * from cszc.plxg_owner_lm where day <> to_date(now())
or (day = to_date(now()) and operateUserId<>20039089);

19.笛卡尔积(交叉连接) CROSS JOIN
交叉连接不带WHERE子句，它返回被连接的两个表所有数据行的笛卡尔积，返回结果集合中的数据行数等于第一个表中的数据行数乘以第二个表中的数据行数

20.SPLIT_PART(string, delimiter, position)  分割
https://blog.csdn.net/neweastsun/article/details/120243524?utm_medium=distribute.pc_relevant.none-task-blog-2~default~baidujs_utm_term~default-0-120243524-blog-113401114.235^v43^control&spm=1001.2101.3001.4242.1&utm_relevant_index=1

20.FULL JOIN
并集，返回两张表都存在的行

21.NULLIF()函数用于比较两个表达式，如果它们的值相等，则返回 NULL，否则返回第一个表达式的值。
IFNULL()函数用于判断第一个表达式是否为 NULL，如果是，则返回第二个表达式的值;否则，返回第一个表达式的值。

22.extract() 函数
用于返回日期/时间的单独部分，比如年、月、日、小时、分钟等
extract(时间,'day')

23.DATEDIFF(end_date,start_date) 时间差
end_date:表示要计算的时间段的结束日期。
start_date:表示要计算的时间段的开始日期
unix_timestamp(end_time) - unix_timestamp(start_time) AS duration_seconds


24.NTILE (expr) OVER ( [ PARTITION BY expression_list ] [ ORDER BY order_list ])：将分区中已排序的行划分为大小尽可能相等的指定数量的已排名组，并返回给定行所在的组。
分组
NTILE(10) OVER (ORDER BY oa_1_3) AS bin_oa_1_3

25.LAG(column_name, offset, default_value) OVER (
  [PARTITION BY partition_column]
  ORDER BY order_column [ASC/DESC]
)
column_name：需要获取前值的列。
offset：向前回溯的行数（默认为1）。
default_value：当无前序数据时的默认值（默认为 NULL）。
PARTITION BY：按指定列分组计算。
ORDER BY：定义排序规则，决定“前一行”的逻辑。

26.逾期金额动态分段
case when start_owing_amount <= 0 then '000.无效区间' -- 不该有的数据
     when start_owing_amount > 3000 then '099.(3000,∞)' -- 数量较少的数据整合
     else concat(lpad(cast(floor((start_owing_amount - 1e-9) / 1000) + 1 as string), 3, '0'), '.(',
                cast(floor((start_owing_amount - 1e-9) / 1000) * 1000 as string), '-',
                cast((floor((start_owing_amount - 1e-9) / 1000) + 1) * 1000 as string),
                ']') end                                                                         as owing_amount_seg -- 以1000为一段，最高为3000+

27.填充函数
1. LPAD (Left Pad) - 左填充
LPAD 函数在字符串的左侧填充指定的字符，直到字符串达到指定的长度。
LPAD(string, target_length, pad_string)
string: 要填充的原始字符串。
target_length: 填充后字符串的总长度。
pad_string: 用于填充的字符（或字符串）。如果省略，在许多数据库系统中默认为空格。
2. RPAD (Right Pad) - 右填充
RPAD 函数在字符串的右侧填充指定的字符，直到字符串达到指定的长度。其语法和 LPAD 完全一样，只是方向不同。
*/


-- 短信
-- 发送表
describe ods.smsmessage_2018;
select *
from ods.smsmessage_2018
where templateid = 5627
;

-- 模板匹配表
describe ods.aimessage;
select * from ods.aimessage where aitemplatealias rlike '2691';

-- 短信黑名单库（用户退订的黑名单）
describe ods.blacklist;

-- 用户回复短信
describe ods.smsmessagemorecord;

-- 部门表
describe ods.department;

-- 模板匹配表
describe ods.messagetemplate;
select * from ods.messagetemplate
where
    templatealias rlike 'tpl_【PPD】1-3t_6141';


-- 汇总
select a.recipient,
       a.content,
       a.templateid,
       a.contenttype,
       case
           when a.contenttype = 1 then '验证码消息'
           when a.contenttype = 2 then '普通消息'
           else '其他' end as contenttype_name,
       a.status,
       case
           when a.status = -1 then '提交失败'
           when a.status = -2 then '发送失败'
           when a.status = -3 then '黑名单拦截'
           when a.status = 0 then '初始化'
           when a.status = 1 then '发送中'
           when a.status = 2 then '提交成功'
           when a.status = 3 then '发送成功'
           else '其他' end as status_name,
       a.aimessageid,-- AiMessageId,可用于区分是否是ai消息
       a.isactive          as send_isactive,
       a.inserttime,
       a.updatetime,
       a.tenementid,
       a.par_dt,
       b.isactive          as template_isactive,
       b.messagekind,
       case
           when b.messagekind = 1 then '验证码'
           when b.messagekind = 2 then '通知'
           when b.messagekind = 3 then '营销'
           when b.messagekind = 4 then '催收'
           else '其他' end as messagekind_name,
       b.templatename,
       b.templatealias,
       b.intervaltime, -- 间隔时间
       b.maxcount, -- 最大发送次数
       b.totalmaxcount, -- 一天总体发送次数
       c.departmentname
from (select * from ods.smsmessage_2018 where par_dt >= '2024-10') a
         left join ods.messagetemplate b
                   on a.templateid = b.templateid
         left join ods.department c
                   on b.departmentid = c.departmentid
where b.isactive = 1 -- 限制在用
--   and b.templatealias = 'tpl_【PPD】1-3t_6141'  -- templateid = 7717
  and b.templatealias = 'tpl_sx_4647' -- 限制模板  templateid = 5627
;
select b.messagekind,
       case
           when b.messagekind = 1 then '验证码'
           when b.messagekind = 2 then '通知'
           when b.messagekind = 3 then '营销'
           when b.messagekind = 4 then '催收'
           else '其他' end as messagekind_name,
       b.templatename,
       b.templatealias,
       b.intervaltime,  -- 间隔时间
       b.maxcount,      -- 最大发送次数
       b.totalmaxcount, -- 一天总体发送次数
       c.departmentname
from ods.messagetemplate b
         left join ods.department c
                   on b.departmentid = c.departmentid
where b.isactive = 1 -- 限制在用
and c.departmentname = '资产保全'
;



-- 催收短信表
select * from edw.b_cs_msg_dly;
select * from ods.messagetemplate
where templatealias = 'tpl_sx_4647';

select max(inserttime) from ods.smsmessage_2018 where templateid = 3954
and to_date(inserttime)>= '2025-01-01';


select * from ods_s.ppdai_ddsms_tb_task_data;-- 短信任务数据表

-- 短信任务发送触达配置，task_id=send_config_id代表一个任务，一个任务里可能有多个分组，对应id字段，里面若有测试对照组会有多个id，一个id代表一个短信模板，
select * from ods.ppdai_ddsms_autosync_2_tb_task_send_touch_config
where isactive = 1
and sms_template = 'tpl_XHF1-3tdl_7134'
;

-- 当前在发送
select
    a.send_touch_config_id,c.templatename,c.templatealias,c.content,b.name,a.overdue_days
from ods_s.ppdai_ddsms_tb_task_data a
left join ods.ppdai_ddsms_autosync_2_tb_task_send_touch_config b
on a.send_touch_config_id = b.id
left join ods.messagetemplate c
on b.sms_template=c.templatealias
where a.day >= '2025-05-01'
and a.isactive = 1
and a.assets_id = 0
and a.task_type = 'messagePlatform'
and c.templatename in (
'【KOO】本人1~7天'
,'【KOO】本人8-120天'
,'【PPD】1-3天(5G阅信)'
,'【智径】koo本人1-7天'
,'【智径】koo本人8-120天'
,'8~120天'
,'M0短信测试（11）本人'
,'M0短信测试（13）本人'
,'M0短信测试（15）本人'
,'M0短信测试（4-5）本人1'
,'M0短信测试（6-7）本人'
,'M0短信测试（8-10）本人'
,'M1短信测试（16）本人'
,'M1短信测试（25-30）本人1'
,'闪信'
    )
group by 1,2,3,4,5,6
;
select * from ods.messagetemplate
where templatealias='tpl_zjzsbr9--15t_6790'
;

select a.*
from ods_s.ppdai_ddsms_tb_task_data a
left join ods.ppdai_ddsms_autosync_2_tb_task_send_touch_config b
on a.send_touch_config_id = b.id
left join ods.messagetemplate c
on b.sms_template=c.templatealias
where a.day >= '2024-12-01'
and a.isactive = 1
and a.assets_id = 0
and a.task_type = 'messagePlatform'
and c.templatename = '逾期1~7天短信提醒-KOO分期'
;
select * from ods.messagetemplate
where  content rlike '您是他的紧急联系人，其在拍拍贷平台上与金融机构的合同已超期'
;
-- 字符串替换函数
-- replace(string str, string search, string replace)
select replace(to_date(now()), '-', '')
;
-- LAST_DAY(date_expression)，返回给定日期所在月份的最后一天（时间戳）。
select last_day(now());
select date_trunc('month',now());-- 返回给定日期所在月份的月初（时间戳）。

-- 获取json字符串中值
select
    -- get_json_object(JSON字符串, '$.键名') 提取值
    get_json_object(json, '$.templateName') as template_name
from ods_s.sendsmstimeslimit;