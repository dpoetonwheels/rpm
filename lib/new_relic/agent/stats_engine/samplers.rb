# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
module Agent
  class StatsEngine
    module Shim # :nodoc:
      def add_sampler(*args); end
      def add_harvest_sampler(*args); end
      def start_sampler_thread(*args); end
    end
    
    # Contains statistics engine extensions to support the concept of samplers
    module Samplers

      # By default a sampler polls on harvest time, once a minute.  However you can
      # override #use_harvest_sampler? to return false and it will sample
      # every POLL_PERIOD seconds on a background thread.
      POLL_PERIOD = 20
      
      # starts the sampler thread which runs periodically, rather than
      # at harvest time. This is deprecated, and should not actually
      # be used - mo threads mo problems
      #
      # returns unless there are actually periodic samplers to run
      def start_sampler_thread

        return if @sampler_thread && @sampler_thread.alive?

        # start up a thread that will periodically poll for metric samples
        return if periodic_samplers.empty?

        @sampler_thread = NewRelic::Agent::AgentThread.new('Sampler Tasks') do
          loop do
            now = Time.now
            begin
              sleep POLL_PERIOD
              poll periodic_samplers
            ensure
              duration = (Time.now - now).to_f
              NewRelic::Agent.record_metric('Supportability/Samplers', duration)
            end
          end
        end
      end


      public

      # Add an instance of Sampler to be invoked about every 10 seconds on a background
      # thread.
      def add_sampler(sampler)
        add_sampler_to(periodic_samplers, sampler)
        log_added_sampler('periodic', sampler)
      end

      # Add a sampler to be invoked just before each harvest.
      def add_harvest_sampler(sampler)
        add_sampler_to(harvest_samplers, sampler)
        log_added_sampler('harvest-time', sampler)
      end

      def harvest_samplers
        @harvest_samplers ||= []
      end

      def periodic_samplers
        @periodic_samplers ||= []
      end


      private

      def add_sampler_to(sampler_array, sampler)
        if sampler_array.any? { |s| s.class == sampler.class }
          NewRelic::Agent.logger.warn "Ignoring addition of #{sampler.inspect} because it is already registered."
        else
          sampler_array << sampler
          sampler.stats_engine = self
        end
      end

      def log_added_sampler(type, sampler)
        ::NewRelic::Agent.logger.debug "Adding #{type} sampler: #{sampler.id}"
      end

      # Call poll on each of the samplers.  Remove
      # the sampler if it raises.
      def poll(samplers)
        samplers.delete_if do |sampled_item|
          begin
            sampled_item.poll
            false # it's okay.  don't delete it.
          rescue => e
            ::NewRelic::Agent.logger.warn "Removing #{sampled_item} from list", e
            true # remove the sampler
          end
        end
      end

    end
  end
end
end
