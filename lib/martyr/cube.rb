module Martyr
  class Cube < BaseCube
    extend Martyr::LevelComparator

    def self.cube
      self
    end

    def self.contained_cube_classes
      [self]
    end

    def self.fact_definitions
      @fact_definitions ||= Schema::FactDefinitionCollection.new(self)
    end

    # Return all dimension definitions regardless of whether they are supported by the cube.
    # A cube +supports+ a dimension only if it calls the #has_dimension_level DSL method.
    # It is quite typical to have multiple cubes inherenting from a context with shared dimensions.
    # So it is typical to have cubes that maintain a reference to a dimension definition they do not support.
    #
    # @see #supported_dimension_definitions to get only the supported dimensions.
    #
    # In the example below, Cube1 does not support shared_dimension_2:
    #
    #   class Common < Martyr::Cube
    #     define_dimension :shared_dimension_1 do
    #       ...
    #     end
    #
    #     define_dimension :shared_dimension_2 do
    #       ...
    #     end
    #   end
    #
    #   class Cube1 < Common
    #     has_dimension_level :shared_dimension_1, :level1
    #   end
    #
    #   Cube1.dimension_definitions.keys
    #   # => ['shared_dimension_1', 'shared_dimension_2']
    #
    # @return [Schema::DimensionDefinitionCollection]
    def self.dimension_definitions
      return @dimension_definitions if @dimension_definitions
      @dimension_definitions = Schema::DimensionDefinitionCollection.new
      @dimension_definitions.merge! parent_schema_class.dimension_definitions if parent_schema_class.present?
      @dimension_definitions
    end

    def self.set_default_fact_grain(*level_ids_arr)
      @default_fact_grain = level_ids_arr
    end

    def self.default_fact_grain
      @default_fact_grain || []
    end

    # @return [Array<LevelAssociation>]
    def self.default_fact_grain_level_associations
      level_association_lookup = level_associations.index_by(&:id)
      default_fact_grain.map do |x|
        level_association_lookup[x] || raise(Schema::Error.new("`#{x}` is in the default fact grain but not connected to the fact query"))
      end
    end

    class << self
      delegate :define_dimension, to: :dimension_definitions
      delegate :main_fact, :build_fact_scopes, :sub_query, to: :fact_definitions
      delegate :has_dimension_level, :has_count_distinct_metric, :has_min_metric, :has_max_metric, # DSL
               :has_sum_metric, :has_custom_metric, :has_custom_rollup, :main_query, # DSL
               :metrics, :find_metric, :dimension_associations, to: :main_fact # Runtime

      delegate :select, :slice, :granulate, :pivot, :build, :granulate_and_select_all, to: :new_query_context_builder
      alias_method :all, :new_query_context_builder

      delegate :combined_sql, to: :granulate_and_select_all
    end

    def self.martyr_schema_class?
      true
    end

    def self.virtual?
      false
    end

    # @return [nil, Base]
    def self.parent_schema_class
      ancestors[1..-1].find { |x| x != self and x.respond_to?(:martyr_schema_class?) }
    end

    # @see comment for #dimension_definitions
    #
    # @return [Schema::DimensionDefinitionCollection] including dimensions that have at least one level
    #   supported by the cube through #has_dimension_level
    def self.supported_dimension_definitions
      dimension_definitions.slice(*dimension_associations.keys)
    end

    # Return all levels that are directly connected to the cube with #has_dimension_level.
    #
    # @return [Array<LevelAssociation>]
    def self.level_associations
      dimension_associations.flat_map { |_name, dimension_association| dimension_association.level_objects }
    end

    # @return [Array<BaseLevelDefinition>]
    def self.supported_level_definitions
      lowest_level_of(level_associations).flat_map do |level_association|
        level_association.level_definition.level_and_above
      end
    end

    # @return [Array<String>]
    def self.supported_level_ids
      supported_level_definitions.map(&:id)
    end

    # Helper methods used to filter out unsupported levels.
    #
    # @param level_ids [Array<String>]
    # @return [Array<String>] all ids that are supported by the cube through the dimension
    def self.select_supported_level_ids(level_ids)
      level_ids = Array.wrap(level_ids)
      unsupported = level_ids - supported_level_ids
      level_ids - unsupported
    end

    # @return [Schema::DependencyInferrer]
    def self.metric_dependency_inferrer
      @metric_dependency_inferrer ||= Schema::DependencyInferrer.new.add_cube_levels(self)
    end

    def self.standardizer
      @standardizer ||= Martyr::MetricIdStandardizer.new(cube_name, raise_if_not_ok: false)
    end

  end
end
