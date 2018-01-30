require 'csv'

desc "This task is used to support DB management"

namespace :db_statistics do
  desc "Manually task to help get current states of DB"
  task all: :environment do
    tasks = [
      # commented the running_queries to indicate that it exists in the list
      # but should not run when generate general reports
      # just call it to know what is going on with the slowly lazy prod DB
      # 'running_queries',
      'table_access_stat',
      'missing_indexes',
      'unused_indexes',
      'duplicated_indexes',
      'table_size'
    ]

    tasks.each { |task| Rake::Task["db_statistics:#{task}"].invoke }
  end

  desc "Find out which queries are running (ie: for long running queries)"
  task running_queries: :environment do |t|
    result = ActiveRecord::Base.connection.exec_query(
      "SELECT
        pid,
        client_addr,
        query,
        state
      FROM pg_stat_activity;"
    )

    CsvResultMailer.send_query_result(result, t.name)
  end

  desc "Find out which table is most frequent accessed and by which way"
  task table_access_stat: :environment do |t|
    result = ActiveRecord::Base.connection.exec_query(
      "SELECT
        schemaname,
        relname,
        seq_scan,
        idx_scan,
        cast(idx_scan AS numeric) / (idx_scan + seq_scan) AS idx_scan_pct
      FROM pg_stat_user_tables WHERE (idx_scan + seq_scan) > 0
      ORDER BY idx_scan_pct;"
    )

    CsvResultMailer.send_query_result(result, t.name)
  end

  desc "Check for missing indexes"
  task missing_indexes: :environment do |t|
    result = ActiveRecord::Base.connection.exec_query(
      "SELECT
        relname,
        seq_scan-idx_scan AS too_much_seq,
        case when seq_scan-idx_scan> 0 THEN 'Missing Index?' ELSE 'OK' END,
        pg_relation_size(relname::regclass) AS rel_size,
        seq_scan,
        idx_scan
      FROM pg_stat_all_tables
      WHERE schemaname='public' AND pg_relation_size(relname::regclass) > 80000
      ORDER BY too_much_seq DESC;"
    )

    CsvResultMailer.send_query_result(result, t.name)
  end

  desc "Find out unused indexes"
  task unused_indexes: :environment do |t|
    result = ActiveRecord::Base.connection.exec_query(
      "SELECT
        relid::regclass AS table,
        indexrelid::regclass AS index,
        pg_size_pretty(pg_relation_size(indexrelid::regclass)) AS index_size,
        idx_tup_read,
        idx_tup_fetch,
        idx_scan
      FROM pg_stat_user_indexes
      JOIN pg_index USING (indexrelid)
      WHERE idx_scan = 0
      ORDER BY pg_relation_size(indexrelid::regclass) DESC;"
    )

    CsvResultMailer.send_query_result(result, t.name)
  end

  desc "Find out duplicate indexes"
  task duplicated_indexes: :environment do |t|
    result = ActiveRecord::Base.connection.exec_query(
      "SELECT
        pg_size_pretty(sum(pg_relation_size(idx))::bigint) AS size,
        (array_agg(idx))[1] AS idx1, (array_agg(idx))[2] AS idx2,
        (array_agg(idx))[3] AS idx3, (array_agg(idx))[4] AS idx4
      FROM (SELECT
              indexrelid::regclass AS idx,
              (indrelid::text ||E'\n' || indclass::text ||E'\n'|| indkey::text ||E'\n'||
              coalesce(indexprs::text,'') || E'\n' || coalesce(indpred::text,'')) AS KEY
            FROM pg_index) sub
      GROUP BY KEY HAVING count(*)>1
      ORDER BY sum(pg_relation_size(idx)) DESC;"
    )

    CsvResultMailer.send_query_result(result, t.name)
  end

  desc "Find out tables size"
  task table_size: :environment do |t|
    result = ActiveRecord::Base.connection.exec_query(
      "SELECT
        relname as \"Table\",
        pg_size_pretty(pg_relation_size(relid)) As \"Table Size\",
        pg_size_pretty(pg_total_relation_size(relid) -
        pg_relation_size(relid)) as \"Index Size\"
      FROM pg_catalog.pg_statio_user_tables
      ORDER BY pg_total_relation_size(relid) DESC;"
    )

    CsvResultMailer.send_query_result(result, t.name)
  end
end
