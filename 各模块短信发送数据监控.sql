-- 7点在催案件信息
drop table if exists test.draft_066836_260526_01;
create table test.draft_066836_260526_01 stored as parquet as
select a.*, b.allot_module_name
from ( select *
       from edw.d_cs_dun_case_snp
       where is_close = 0
         and dt = to_date(date_sub(now(), 1))
         and isactive = 1
         and assets_id = 81
         and max_default_days < 91 ) a
         join ( select user_id, allot_module_name, group_id, dt
                from edw.dim_cs_owner_all_snp
                where dt = to_date(date_sub(now(), 1)) ) b on a.own_id = b.user_id and a.dt = b.dt
;


-- 获取小辉付用户号码，dt表示前一天推送，与短信表匹配要+1
drop table if exists test.draft_066836_260526_02;
create table test.draft_066836_260526_02 stored as parquet as
select a.*, b.phone, b.order_id, b.ph_from
from test.draft_066836_260526_01 a
         left join [shuffle] ( select dt,
                            user_id,
                            phone,
                            case when order_id = 1 then '本人' else '三方' end as order_id,
                            '号码推荐'                                         as ph_from
                     from ddm.cs_user_phone_recommend_dl_dly
                     where dt = to_date(date_sub(now(), 2))
                       and user_id between 1800000000 and 1900000000
                     union
                     select to_date(date_add(t0.dt, -1))                                        as dt,
                            t0.user_id,
                            t0.customer_tel                                                     as phone,
                            case when t0.send_realtionship = '本人' then '本人' else '三方' end as order_id,
                            '客服&自填'                                                         as ph_from
                     from ( select *
                            from ( select dt,
                                          user_id,
                                          customer_tel,
                                          send_realtionship,
                                          row_number() over (partition by dt, user_id, customer_tel order by msg_time desc) as rk -- 号码关系不准确，取当天最后一条短信发送时的关系
                                   from edw.b_cs_msg_dly
                                   where dt =  to_date(date_sub(now(), 1))
                              and user_id between 1800000000 and 1900000000
                                 ) tmp
                            where rk = 1 ) t0
                              left anti join ddm.cs_user_phone_recommend_dl_dly t1
                                   on t0.dt = to_date(date_add(t1.dt, 1)) and t0.user_id = t1.user_id and
                                      t0.customer_tel = t1.phone ) b
                   on a.user_id = b.user_id and a.dt = to_date(date_add(b.dt, 1))
;


-- 短信发送明细
drop table if exists test.draft_066836_260526_03;
create table test.draft_066836_260526_03 stored as parquet as
with t0 as ( select t0.template_name, t0.id, t0.display_name, t1.relation_value
             from ods.ppdai_dds_autosync_2_dim_dun_sms_template t0
                      left join ods.ppdai_ddsms_tb_sms_template_relation_info t1
                                on t0.id = t1.template_id and t1.relation_type = 'smsAttribute' -- smsAttribute 这个指的是短信，relation_value= dunSms是催收类
             where t0.isactive = 1
               and t0.template_name is not null
             group by 1, 2, 3, 4 )
select t1.dt                                                                        as insert_dt,
       t1.user_id,
       t1.dun_case_id,
       t1.assets_id,
       t1.phone,
       t1.sms_template,
       t0.display_name,
       t1.message_id,
       t1.inserttime,
       t1.result_message,
       t1.admin_user_id,
       case when t0.relation_value is null then 'dunSms' else t0.relation_value end as relation_value,
       '系统'                                                                       as message_type,
       t2.task_type
from ( select *
       from ( select dt,
                     user_id,
                     dun_case_id,
                     assets_id,
                     mobile_phone                                                            as phone,
                     sms_template,
                     message_id,
                     inserttime,
                     result_message,
                     admin_user_id,
                     row_number() over (partition by message_id,dt order by updatetime desc) as rk
              from edw.d_cs_msg_record_dly
              where dt =  to_date(date_sub(now(), 1))
                and message_id <> ""
                and assets_id = 81 ) tmp
       where rk = 1 ) t1
         left join t0 on t0.template_name = t1.sms_template
         left join ods_s.ppdai_ddsms_tb_task_data t2
                   on t1.message_id = t2.message_id and to_date(t2.inserttime) = t1.dt and t2.message_id <> ""

union all

select dt                                                                                                         as insert_dt,
       user_id,
       dun_case_id,
       assets_id,
       mobile                                                                                                     as phone,
       ""                                                                                                         as sms_template,
       ""                                                                                                         as display_name,
       'zzy'                                                                                                      as message_id,
       inserttime,
       case when status = 3 then '发送成功'
            when status = 2 then '发送失败'
            when status = 1
                then 'zzy-提交中' end                                                                             as result_message,
       owner_id                                                                                                   as admin_user_id,
       'dunSms'                                                                                                   as relation_value,
       '指掌易'                                                                                                   as message_type,
       '指掌易'                                                                                                   as task_type
from edw.d_cs_msg_zhizhangyi_dly
where dt =  to_date(date_sub(now(), 1))
  and action_type = 1
  and assets_id = 81
;


insert overwrite table cszc.066836_msg_detail_20260529
select * from cszc.066836_msg_detail_20260529
where dt <> to_date(date_sub(now(), 1))
union
select t0.dt,
       t0.user_id,
       t0.dun_case_id,
       t0.own_id,
       t0.allot_module_name,
       t0.phone,
       t0.order_id,
       t0.ph_from,
       t1.message_id,
       t1.inserttime,
       t1.sms_template,
       t1.display_name,
       t1.result_message,
       t1.admin_user_id,
       t1.message_type,
       case when t1.task_type = 'ownerBatchTask' then '跨案件批量触发'
            when t1.task_type = 'ownerSingleCaseTask' then '单案件批量触发'
            when t1.message_type = '系统' and t1.admin_user_id > 0 then '手工触发106'
            when t1.message_type = '指掌易' then '手工触发指掌易'
            when t1.sms_template is not null then '系统触发'
            else '未触发' end                                                             task_type,
       t1.relation_value
from test.draft_066836_260526_02 t0
         left join [shuffle] test.draft_066836_260526_03 t1
                   on t0.phone = t1.phone and t0.user_id = t1.user_id and t0.dun_case_id = t1.dun_case_id and t0.dt = t1.insert_dt
-- group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17
;


select substr(dt, 1, 7)                                                                              as mth,
       dt,
       allot_module_name,
       count(distinct user_id)                                                                       as user_cnt,
       count(case when message_id is not null then message_id end)                                   as msg_cnt,
       count(case when message_id is not null and message_type = '系统' then message_id end)         as sys_msg_cnt,
       count(case when message_id is not null and message_type = '指掌易' then message_id end)       as zzy_msg_cnt,
       count(distinct case when message_id is not null then user_id end)                             as send_user_cnt,
       count(distinct case when message_id is not null and message_type = '系统'
                               then user_id end)                                                     as sys_send_user_cnt,
       count(distinct case when message_id is not null and message_type = '指掌易'
                               then user_id end)                                                     as zzy_send_user_cnt
from cszc.066836_msg_detail_20260529
where allot_module_name in
      ('小辉付_M1中额', '小辉付_M0小额人工', '云金_M2', '云金_M3', '小辉付_M0_2_8', '小辉付_M1大额', '小辉付_M0风险组',
       '小辉付_M0_9_15', '云金_易投诉_1-90', '云金_1-1',
       '小辉付_M0小额大模型AI')
group by 1, 2, 3
;
