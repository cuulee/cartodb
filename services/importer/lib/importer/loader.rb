# encoding: utf-8
require_relative './ogr2ogr'
require_relative './csv_normalizer'
require_relative './json2csv'
require_relative './xlsx2csv'
require_relative './georeferencer'

module CartoDB
  module Importer2
    class Loader
      SCHEMA        = 'cdb_importer'
      TABLE_PREFIX  = 'importer'
      NORMALIZERS   = [CsvNormalizer, Xlsx2Csv, Json2Csv]

      def initialize(job, source_file, ogr2ogr=nil, georeferencer=nil)
        self.job            = job
        self.source_file    = source_file
        self.ogr2ogr        = ogr2ogr
        self.georeferencer  = georeferencer
      end #initialize

      def run
        job.log "Using database connection with #{job.concealed_pg_options}"
        normalize

        ogr2ogr.run
        job.log "ogr2ogr output:    #{ogr2ogr.command_output}"
        job.log "ogr2ogr exit code: #{ogr2ogr.exit_code}"

        georeferencer.run
        self
      end #run

      def normalize
        converted_filepath = normalizers_for(source_file.extension)
          .inject(source_file.fullpath) { |filepath, normalizer_klass|
            normalizer_klass.new(filepath, job).run.converted_filepath
          }
        self.source_file = SourceFile.new(converted_filepath)
        self
      end #normalize

      def ogr2ogr
        @ogr2ogr ||= 
          Ogr2ogr.new(job.table_name, source_file.fullpath, job.pg_options)
      end #ogr2ogr

      def georeferencer
        @georeferencer ||= 
          Georeferencer.new(job.db, job.table_name, SCHEMA, job)
      end #georeferencer

      def valid_table_names
        [job.table_name]
      end #valid_table_names

      def normalizers_for(extension)
        NORMALIZERS.find_all { |klass| klass.supported?(extension) }
      end #normalizers_for

      private

      attr_writer     :ogr2ogr, :georeferencer
      attr_accessor   :job, :source_file
    end # Loader
  end # Importer2
end # CartoDB

