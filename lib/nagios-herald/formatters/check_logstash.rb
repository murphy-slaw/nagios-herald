# CheckDisk formatter
# Colorizes and bolds text generated by the 'check_disk' NRPE check.

module NagiosHerald
  class Formatter
    class CheckLogstash < NagiosHerald::Formatter
      include NagiosHerald::Logging

      # Public: Overrides Formatter::Base#additional_info.
      # Calls on methods defined in this class to generate stack bars and download
      # Ganglia graphs.
      #
      # Returns nothing. Updates the formatter content hash.
      def additional_info
        section = __method__  # this defines the section key in the formatter's content hash
        service_output = get_nagios_var("NAGIOS_SERVICECHECKCOMMAND")
        command_components =  parse_command(service_output)

        # The aggregation level limit for which we can render results
        agg_level_limit = 3

        logstash_helper = NagiosHerald::Helpers::LogstashQuery.new
        results = get_logstash_results(logstash_helper, command_components[:query])

        # Handle the case when an exception is thrown inside get_logstash_results
        if results.empty?
          add_text(section, "Something went wrong while getting logstash results\n\n")
          return
        end

        if results["hits"]["hits"].empty? && results["aggregations"]
          # We have aggregations

          query_agg_data = logstash_helper.query["aggregations"] || logstash_helper.query["aggs"]

          agg_depth_level = 1 + agg_depth(query_agg_data)

          # We can't cope with more than 3 level deep aggregates
          if agg_depth_level > agg_level_limit
            #Add error text to the alert and return straight away
            add_text(section, "Error - query contains #{agg_depth_level} levels of aggregation - more than #{agg_level_limit} levels are not supported by this plugin\n")
            return
          end

          agg_field_name = query_agg_data.keys.first

          html_output = generate_table_from_buckets(results["aggregations"][agg_field_name]["buckets"])
        else
          # We have normal search results
          html_output = generate_html_output(results["hits"]["hits"])
        end

        add_html(section, html_output)
      end

      # Public: Overrides Formatter::Base#additional_details.
      # Calls on methods defined in this class to colorize and bold the `df` output
      # generated by the check_disk NRPE check.
      #
      # Returns nothing. Updates the formatter content hash.
      def additional_details

      end

      private

      def parse_command(service_command)
        command_components = service_command.split("!")
        {
            :command => command_components[0],
            :query => command_components[1],
            :warn_threshold => command_components[2],
            :crit_threshold => command_components[3],
            :time_perdiod => command_components[4]
        }
      end

      def agg_depth(agg_data)
        agg_level = 0
        if agg_data.kind_of?(String)
          agg_level = agg_data.include?("aggs") || agg_data.include?("aggregations") ? 1 : 0
        else
          agg_data.each do |k,v|
            this_level = k.include?("aggs") || k.include?("aggregations") ? 1 : 0
            agg_level = this_level + agg_depth(v)
          end
        end
        agg_level
      end

      def get_logstash_results(logstash_helper, query)
        begin
          if query.include?(".json")
            logstash_helper.query_from_file(query)
          else
            logstash_helper.kibana_style_query(query)
          end
        rescue Exception => e
          logger.error "Exception encountered retrieving Logstash Query - #{e.message}"
          e.backtrace.each do |line|
            logger.error "#{line}"
          end
          return []
        end
      end

      def generate_html_output(results)
        output_prefix = "<table border='1' cellpadding='0' cellspacing='1'>"
        output_suffix = "</table>"

        headers = "<tr>#{results.first["_source"].keys.map{|h|"<th>#{h}</th>"}.join}</tr>"
        result_values = results.map{|r|r["_source"]}

        body = result_values.map{|r| "<tr>#{r.map{|k,v|"<td>#{v}</td>"}.join}</tr>"}.join

        output_prefix + headers + body + output_suffix
      end

      def generate_table_from_buckets(buckets)
        unique_keys = buckets.map{|b|b.keys}.flatten.uniq

        output_prefix = "<table border='1' cellpadding='0' cellspacing='1'>"
        output_suffix = "</table>"
        headers = "<tr>#{unique_keys.map{|h|"<th>#{h}</th>"}.join}</tr>"
        body = buckets.map do |r|
          generate_table_from_hash(r)
        end.join
        output_prefix + headers + body + output_suffix
      end

      def generate_table_from_hash(data,add_headers=false)
        output_prefix = "<table border='1' cellpadding='0' cellspacing='1'>"
        output_suffix = "</table>"
        headers = add_headers ? "<tr>#{data.keys.map{|h|"<th>#{h}</th>"}.join}</tr>" : ""
        body = "<tr>#{data.map do |k,v|
            if v.kind_of?(Hash)
              if v.has_key?("buckets")
                "<td>#{generate_table_from_buckets(v["buckets"])}</td>"
              else
                "<td>#{generate_table_from_hash(v,true)}</td>"
              end
            else
              "<td>#{v}</td>"
            end
        end.join}</tr>"

        if add_headers
          output_prefix + headers + body + output_suffix
        else
          body
        end
      end
    end
  end
end
