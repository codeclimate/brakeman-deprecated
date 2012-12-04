require "brakeman/app_tree"
require "grit"
require "bertrpc"
require "uri"

module Brakeman
  class SmokeAppTree < AppTree
    BRANCH_NAME = "origin/master"

    def initialize(url, skip_files = nil)
      @uri = URI.parse(url)
      @skip_files = skip_files
    end

    def valid?
      true
    end

    def expand_path(path)
      raise "TODO expand_path"
    end

    def read(path)
      grit_repo.blob(file_index[path]).data
    end

    def read_path(path)
      read(path)
    end

    def path_exists?(path)
      raise "TODO path_exists?"
    end


    def exists?(path)
      file_index[path]
    end

    def layout_exists?(name)
      !glob("app/views/layouts/#{name}.html.{erb,haml}").empty?
    end

  private

    def find_paths(directory, extensions = "*.rb")
      (glob("#{directory}/**/#{extensions}") +
      glob("#{directory}/#{extensions}")).uniq
    end

    def glob(pattern)
      file_index.keys.select do |path|
        File.fnmatch(pattern, path)
      end
    end

    def file_index
      @file_index = Hash.new.tap do |index|
        deep_tree(commit.tree.id).contents.each do |content|
          index[content.name] = content.id
        end
      end
    end

    def deep_tree(tree_id)
      output = grit_repo.git.native(:ls_tree, { r: true }, tree_id)
      ::Grit::Tree.allocate.construct_initialize(grit_repo, tree_id, output)
    end

    def commit
      @commit ||= ref.commit
    end

    def ref
      @ref ||= grit_repo.refs.find { |r| r.name == BRANCH_NAME }
    end

    def grit_repo
      @grit_repo ||= ::Grit::Repo.allocate.tap do |r|
        r.path = "#{@uri.path.split("/").last}.git"
        r.git = SmokeClient.new(@uri)
      end
    end

    class SmokeClient
      DEFAULT_TIMEOUT = 20

      def initialize(uri, timeout = nil)
        @uri = uri
        @timeout = timeout
      end

      def method_missing(remote_method_name, *args)
        mod.send(remote_method_name, repo_id.to_s, *args)
      end

      def repo_id
        @uri.path.split("/").last
      end

      def mod
        service.call.send(module_name)
      end

      def service
        @service ||= ::BERTRPC::Service.new(@uri.host, @uri.port, @timeout || DEFAULT_TIMEOUT)
      end

      def module_name
        @module_name ||= @uri.path.sub(/^\//, "").split("/").first
      end
    end

  end
end
