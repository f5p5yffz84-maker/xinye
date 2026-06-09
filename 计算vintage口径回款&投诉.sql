-- 模块内回收mtd，案件号和dt是主键
drop table if exists cszc.066836_lawyer_letter_test_total_jx_mtd;
create table cszc.066836_lawyer_letter_test_total_jx_mtd stored as parquet as
with jx as (select user_id,
                   dun_case_id,
                   model_dc,
                   min(allot_time_simple)                             as min_allot_time,
                   SUM(case when rn = 1 then startowingamount_kc end) as start_owing_amount,
                   SUM(dun_repay_amount)                              as dun_repay_amount
            from (select *
                       , row_number() over (partition by model_dc,dun_case_id,product_id,period_id order by allot_time) as rn
                  from cszc.dl_mrjx_dp_stats
                  where model_dc in ('云金_M2', '云金_M3')) a --主营cszc.mrjx_dp_stats,overduemaxdays_fab分案时案件逾期天数
            group by 1, 2, 3)
select base.user_id
     , base.user_name
     , base.real_name
     , base.dun_case_id
     , base.group_id
     , base.allot_module_name
     , base.max_default_days
     , base.owing_amount
     , base.due_amount
     , base.owing_amount_future
     , base.idcard_ocr_data_address
     , base.len_id
     , base.idnumber
     , base.phone
     , base.is_able
     , base.lawyer_flag
     , base.test_flag
     , cast(jx.start_owing_amount as decimal(38, 14)) start_owing_amount
     , cast(jx.dun_repay_amount as decimal(38, 14))   dun_repay_amount
     , base.dt
from (select *
      from cszc.066836_lawyer_letter_test_total_list_snp
      where dt < to_date(now())) base -- 没有当天的数据
         left join jx
                   on base.dun_case_id = jx.dun_case_id
                       and base.dt = jx.min_allot_time
                       and base.allot_module_name = jx.model_dc
;


-- vintage口径
drop table if exists test.066836_draft_250507_00;
create table if not exists test.066836_draft_250507_00 stored as parquet as
select a.dun_case_id
     , a.borrow_user_id     as user_id
     , b.owing_amount       as oa_d3
     , to_date(a.time_mark) as dt -- 以防存在回滚，主键是dun_case_id和dt
from ods.tb_case_allocation a
         join ( select *
                from edw.tb_dun_case_snp
                where dt between '2025-12-01' and '2026-02-28'
                  and dun_close_reason_id = 0
                  and assets_id in (0, 81)
                  and max_default_days = 3 ) b
              on a.dun_case_id = b.dun_case_id and to_date(adddate(a.time_mark, 2)) = b.dt
where to_date(a.time_mark) >= ${dt}
  and a.admin_id = 1564362
  and a.record_type = 1 -- type1即owner分案，1：Owner分案，2：Owner清空，3：Case关闭
  and a.overdue_max_days = 1
  and a.isactive = 1
  and a.assets_id in (0, 81)
group by 1, 2, 3, 4
;
drop table if exists test.066836_draft_250507_01;
create table test.066836_draft_250507_01 stored as parquet as
with t0 as (select a.detail_id,
                   a.allocation_id,
                   a.dun_case_id,
                   a.user_id,
                   a.product_id,
                   a.period_id,
                   a.allot_time,
                   a.overdue_max_days,
                   a.start_owing_amount,
                   a.start_owing_principal,
                   b.dt as dt
            from ods.tb_case_allocation_detail a
                     inner join test.066836_draft_250507_00 b
                                on a.dun_case_id = b.dun_case_id
                                    and to_date(a.allot_time) >= b.dt
                                    and to_date(a.allot_time) < to_date(adddate(b.dt, 30))
            -- 每月跑批时根据实际情况修改天数跨度
            where to_date(a.allot_time) >= ${dt}
              and to_date(a.allot_time) < to_date(now())
              and a.dun_repay_status_id <> 2 -- 剔除分案前还款
              and a.isactive = 1),
     t1 as (select t0.*,
                   row_number() over (partition by dun_case_id,product_id,period_id,dt order by allot_time) as rn -- 一个案件可能跨模块
            from t0)
select detail_id,
       allocation_id,
       dun_case_id,
       user_id,
       product_id,
       period_id,
       allot_time,
       datediff(to_date(allot_time), dt) as diffdays,
       overdue_max_days,
       start_owing_amount,
       start_owing_principal,
       dt
from t1
where rn = 1;
-- 每个标的取第一条分案时逾期金额


--计算回款金额
--根据逾期案件的每笔listing,每笔loan计算回款
drop table if exists test.066836_draft_250507_02;
create table test.066836_draft_250507_02 stored as parquet as
with t0 as (select a.record_id,
                   a.dun_case_id,
                   a.product_id,
                   a.period_id,
                   a.total_amount,
                   a.principal,
                   to_date(a.repayment_time)                 as rp_dt,
                   b.dt,
                   datediff(to_date(a.repayment_time), b.dt) as diffdays
            from ods.tb_repayment_record a
                     inner join test.066836_draft_250507_01 b
                                on a.dun_case_id = b.dun_case_id
                                    and a.product_id = b.product_id
                                    and a.period_id = b.period_id
                                    and a.repayment_time >= b.allot_time
                                    and a.repayment_time < to_date(adddate(b.dt, 30))
            -- 每月跑批时根据实际情况修改天数跨度
            where to_date(a.repayment_time) >= ${dt}
              and to_date(a.repayment_time) < to_date(now()))
select dun_case_id,
       dt,
       diffdays,
       sum(total_amount) as repay_amount,
       sum(principal)    as repay_principal
from t0
group by 1, 2, 3
;

-- 匹配逾期和回款，计算回款率
drop table if exists test.066836_draft_250507_03;
create table test.066836_draft_250507_03 stored as parquet as
with t0 as (select t0.dun_case_id
                 , t0.dt
                 , sum(case when t1.diffdays < 10 then t1.start_owing_amount else 0 end) as oa_10
                 , sum(case when t1.diffdays < 20 then t1.start_owing_amount else 0 end) as oa_20
                 , sum(case when t1.diffdays < 30 then t1.start_owing_amount else 0 end) as oa_30
            from (select * from cszc.066836_lawyer_letter_test_total_list_snp where dt < to_date(now())) t0
                     left join test.066836_draft_250507_01 t1 on t0.dun_case_id = t1.dun_case_id and t0.dt=t1.dt
            group by 1, 2)
select t0.dun_case_id
     , t0.dt
     , t0.oa_10
     , t0.oa_20
     , t0.oa_30
     , sum(case when t2.diffdays < 10 then t2.repay_amount else 0 end) as ra_10
     , sum(case when t2.diffdays < 20 then t2.repay_amount else 0 end) as ra_20
     , sum(case when t2.diffdays < 30 then t2.repay_amount else 0 end) as ra_30
from t0
         left join test.066836_draft_250507_02 t2 on t0.dun_case_id = t2.dun_case_id and t0.dt=t2.dt
group by 1, 2, 3, 4, 5
;


-- 投诉
drop table if exists test.066836_draft_250507_04;
create table test.066836_draft_250507_04 stored as parquet as
select
    t1.*
    , nvl(t2.ts_level,'other') ts_level
from
(
    select * from ddm.csc_complaint_cs_detail
    where isactive = 1
        and department = '催收'
        and to_date(inserttime) >= ${dt}
) t1
left join
(
    select complaintchannel,complaintfrom,ts_level
    from cszc.lyf_zj_ts_level_category-- 质检投诉口径
    group by 1,2,3
) t2
on t1.complaint_channel = t2.complaintchannel
    and t1.complaint_from = t2.complaintfrom
;

--案件维度分逾期天数看投诉
drop table if exists test.066836_draft_250507_05;
create table test.066836_draft_250507_05 stored as parquet as
with base as ( select * from cszc.066836_lawyer_letter_test_total_list_snp where dt < to_date(now()) ),
     complaint_stats as ( select a.dun_case_id,
                                 a.dt,
                                 count(case when datediff(to_date(b.inserttime), a.dt) < 10 then 1 end) as cnt_ts_yq_10_dt,
                                 count(case when datediff(to_date(b.inserttime), a.dt) < 10 and
                                                 b.ts_level in ('一级', '二级')
                                                then 1 end)                                             as cnt_1_2_level_ts_tq_10_dt,

                                 count(case when datediff(to_date(b.inserttime), a.dt) < 20 then 1 end) as cnt_ts_yq_20_dt,
                                 sum(case when datediff(to_date(b.inserttime), a.dt) < 20 and
                                               b.ts_level in ('一级', '二级')
                                              then 1 end)                                               as cnt_1_2_level_ts_tq_20_dt,

                                 count(case when datediff(to_date(b.inserttime), a.dt) < 30 then 1 end) as cnt_ts_yq_30_dt,
                                 sum(case when datediff(to_date(b.inserttime), a.dt) < 30 and
                                               b.ts_level in ('一级', '二级')
                                              then 1 end)                                               as cnt_1_2_level_ts_tq_30_dt
                          from base a
                                   left join test.066836_draft_260312_04 b
                                             on a.dun_case_id = b.dun_case_id and to_date(b.inserttime) >= a.dt and
                                                to_date(b.inserttime) < to_date(date_add(a.dt, 30))
                          group by a.dun_case_id, a.dt )
select t0.dun_case_id,
       t0.dt,
       nvl(t1.cnt_ts_yq_10_dt, 0)           as cnt_ts_yq_10_dt,
       nvl(t1.cnt_1_2_level_ts_tq_10_dt, 0) as cnt_1_2_level_ts_tq_10_dt,
       nvl(t1.cnt_ts_yq_20_dt, 0)           as cnt_ts_yq_20_dt,
       nvl(t1.cnt_1_2_level_ts_tq_20_dt, 0) as cnt_1_2_level_ts_tq_20_dt,
       nvl(t1.cnt_ts_yq_30_dt, 0)           as cnt_ts_yq_30_dt,
       nvl(t1.cnt_1_2_level_ts_tq_30_dt, 0) as cnt_1_2_level_ts_tq_30_dt
from base t0
         left join complaint_stats t1 on t0.dun_case_id = t1.dun_case_id and t0.dt = t1.dt
;

drop table if exists cszc.066836_lawyer_letter_test_jx_complaint;
create table cszc.066836_lawyer_letter_test_jx_complaint stored as parquet as
select base.user_id
     , base.user_name
     , base.real_name
     , base.dun_case_id
     , base.group_id
     , base.allot_module_name
     , base.max_default_days
     , base.owing_amount
     , base.due_amount
     , base.owing_amount_future
     , base.idcard_ocr_data_address
     , base.len_id
     , base.idnumber
     , base.phone
     , base.is_able
     , base.lawyer_flag
     , base.test_flag
     , base.dt
     , mtd.start_owing_amount                                     as mtd_oa
     , mtd.dun_repay_amount                                       as mtd_ra
     , vintage.oa_10                                              as vtg_oa_10
     , vintage.oa_20                                              as vtg_oa_20
     , vintage.oa_30                                              as vtg_oa_30
     , vintage.ra_10                                              as vtg_ra_10
     , vintage.ra_20                                              as vtg_ra_20
     , vintage.ra_30                                              as vtg_ra_30
     , ts.cnt_ts_yq_10_dt
     , ts.cnt_1_2_level_ts_tq_10_dt
     , ts.cnt_ts_yq_20_dt
     , ts.cnt_1_2_level_ts_tq_20_dt
     , ts.cnt_ts_yq_30_dt
     , ts.cnt_1_2_level_ts_tq_30_dt
     , case when datediff(now(), base.dt) >= 10 then 1 else 0 end as is_arrive10
     , case when datediff(now(), base.dt) >= 20 then 1 else 0 end as is_arrive20
     , case when datediff(now(), base.dt) >= 30 then 1 else 0 end as is_arrive30
from (select *
      from cszc.066836_lawyer_letter_test_total_list_snp
      where dt < to_date(now())) base --锁定案件和测试日期，唯一主键
         left join cszc.066836_lawyer_letter_test_total_jx_mtd mtd
                   on base.dun_case_id = mtd.dun_case_id and base.dt = mtd.dt
         left join test.066836_draft_250507_03 vintage
                   on base.dun_case_id = vintage.dun_case_id and base.dt = vintage.dt
         left join test.066836_draft_250507_05 ts
                   on base.dun_case_id = ts.dun_case_id and base.dt = ts.dt
;

-- 看板汇总结果
select allot_module_name,
       lawyer_flag,
       dt,
       substr(dt, 1, 7)               as mth,
       substr(dt, 9, 2)               as day,
       is_arrive10,
       is_arrive20,
       is_arrive30,
       CASE
           WHEN owing_amount_future <= 1000 THEN '0.无效区间'
           when owing_amount_future > 3000 then '4.(3000,∞)'
           ELSE CONCAT(
                   LPAD(cast(FLOOR((owing_amount_future - 1e-9) / 1000) as string), 1, '0'),
                   '.(',
                   cast(FLOOR((owing_amount_future - 1e-9) / 1000) * 1000 as string),
                   '-',
                   cast((FLOOR((owing_amount_future - 1e-9) / 1000) + 1) * 1000 as string),
                   ']'
                )
           END                        AS owing_amount_seg,
       count(1) as case_cnt,
       sum(mtd_oa)                    as mtd_oa,
       sum(mtd_ra)                    as mtd_ra,
       sum(vtg_oa_10)                 as vtg_oa_10,
       sum(vtg_oa_20)                 as vtg_oa_20,
       sum(vtg_oa_30)                 as vtg_oa_30,
       sum(vtg_ra_10)                 as vtg_ra_10,
       sum(vtg_ra_20)                 as vtg_ra_20,
       sum(vtg_ra_30)                 as vtg_ra_30,
       sum(cnt_ts_yq_10_dt)           as cnt_ts_yq_10_dt,
       sum(cnt_1_2_level_ts_tq_10_dt) as cnt_1_2_level_ts_tq_10_dt,
       sum(cnt_ts_yq_20_dt)           as cnt_ts_yq_20_dt,
       sum(cnt_1_2_level_ts_tq_20_dt) as cnt_1_2_level_ts_tq_20_dt,
       sum(cnt_ts_yq_30_dt)           as cnt_ts_yq_30_dt,
       sum(cnt_1_2_level_ts_tq_30_dt) as cnt_1_2_level_ts_tq_30_dt
from cszc.066836_lawyer_letter_test_jx_complaint
group by 1, 2, 3, 4, 5, 6, 7, 8, 9
;