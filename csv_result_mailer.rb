class CsvResultMailer

  DEFAULT_RECIPIENT = 'phamtuan2993@gmail.com'
  DEFAULT_SENDER = Figaro.env.DEFAULT_SENDER || "db_statistic_rake@gmail.com"

  class << self
    def csv_from_result(result)
      CSV.generate(headers: true) do |csv|
        csv << result.columns
        result.rows.each do |row|
          csv << row
        end
      end
    end

    def send_query_result(result, task_name)
      result_csv = csv_from_result(result)

      request = PostageApp::Request.new(
        :send_message,
        headers: {
          from: DEFAULT_SENDER,
          subject: "Reporting for #{task_name}"
        },
        recipients: DEFAULT_RECIPIENT,
        content: {
          'text/plain' => 'Please check the rake task query result in the attachment'
        },
        attachments: {
          'result.csv' => {
            content_type: 'text/comma-separated-values',
            content: Base64.encode64(result_csv)
          }
        }
      )

      request.send
    end
  end
end
