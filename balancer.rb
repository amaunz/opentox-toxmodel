# cuts a classification dataset into balanced pieces
# let inact_act_ratio := majority_class.size/minority_class.size 
# then: nr pieces = ceil(inact_act_ratio) if inact_act_ratio > 1.5
# each piece contains the complete minority class and ceil(inact_act_ratio) majority class compounds.

class Balancer

  attr_accessor :inact_act_ratio, :act_hash, :inact_hash, :majority_splits, :nr_majority_splits, :errors, :datasets

  # Supply a OpenTox::Dataset here
  # Calculates inact_act_ratio, iff inact_act_ratio != +/-Infinity and no regression dataset is given
  def initialize(dataset, feature_uri, creator_url)
    @act_arr = []
    @inact_arr = []
    @inact_act_ratio = 1.0/0  # trick to define +infinity
    @nr_majority_splits = 1   # +/-1 means: no split
    @split = []               # splitted arrays with ids
    @datasets = []            # result datasets
    @errors = []

    classification = true
    if dataset.features.include?(feature_uri)
      dataset.data.each do |i,a|
        inchi = i
        acts = a
        acts.each do |act|
          value = act[feature_uri]
          if OpenTox::Utils.is_true?(value)
            @act_arr << inchi
          elsif OpenTox::Utils.classification?(value)
            @inact_arr << inchi
          else
            classification = false
            break;
          end
        end
      end
      @inact_act_ratio = @inact_arr.size.to_f / @act_arr.size.to_f unless (@act_arr.size == 0 or !classification) # leave alone for regression
      set_nr_majority_splits
      # perform majority split
      @split = @nr_majority_splits > 0 ? shuffle_split(@inact_arr) : shuffle_split(@act_arr) unless @nr_majority_splits.abs == 1
      @split.each do |s|
        new_c = @nr_majority_splits > 0 ? s.concat(@act_arr) : s.concat(@inac_arr)
        @datasets << dataset.create_new_dataset(new_c, [feature_uri], dataset.title, creator_url)
      end

    else
      errors << "Feature not present in dataset."
    end
    errors << "Can not split regression dataset." unless classification
  end



  # sets nr of splits for majority class ('+', if inact_cnt > act_cnt, or '-' else), or leaves unchanged for illegal values.
  def set_nr_majority_splits
    @nr_majority_splits = @inact_act_ratio >= 1.5 ? @inact_act_ratio.ceil : ( @inact_act_ratio <= (2.0/3.0) ? -(1.0/@inact_act_ratio).ceil : ( @inact_act_ratio>1.0 ? 1 : -1) ) unless OpenTox::Utils.infinity?(@inact_act_ratio) # leave alone for regression
  end

  # does the actual shuffle and split
  def shuffle_split (arr)
    arr = arr.shuffle
    arr.chunk(@nr_majority_splits.abs)
  end

  # turns a hash into a 2 col csv
  def hsh2csv (hsh)
    res=""
    hsh.each do |k,v|
      arr = [v,(@nr_majority_splits > 0 ? 0 : 1)]
      res += arr.join(", ") + "\n"
    end
    res
  end

end

class Array

  # cuts an array into <num-pieces> chunks - returns a two-dimensional array
  def chunk(pieces)
    q, r = length.divmod(pieces)
    (0..pieces).map { |i| i * q + [r, i].min }.enum_cons(2) \
      .map { |a, b| slice(a...b) }
  end

  # shuffles the elements of an array
  def shuffle( seed=nil )
    srand seed.to_i if seed
    sort_by { Kernel.rand }
  end

  # shuffels self
  def shuffle!( seed=nil )
    self.replace shuffle( seed )
  end

end
