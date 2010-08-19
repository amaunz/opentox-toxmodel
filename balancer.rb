class Array

  # cuts an array into <num-pieces> chunks
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

class Balancer

  attr_accessor :inact_act_ratio, :act_hash, :inact_hash, :majority_splits, :nr_majority_splits

  def initialize(parser)
    @act_hash = {}
    @inact_hash = {}
    @act_cnt = 0
    @inact_cnt = 0
    @inact_act_ratio = 1.0/0 # trick to define +infinity
    @majority_splits = []
    @nr_majority_splits = 1 # +/-1 means: no split

    if parser.type == "classification" 
      parser.data.each do |d|
        smi = OpenTox::RestClientWrapper.get(d[0],:accept => "chemical/x-daylight-smiles")
        act = d[1]
        id  = d[2]
        if parser.is_true?(act)
          @act_cnt += 1
          @act_hash[id]=smi
        else 
          @inact_cnt += 1
          @inact_hash[id]=smi
        end
      end
      @inact_act_ratio = @inact_cnt.to_f / @act_cnt.to_f unless @act_cnt == 0 
    end
  end

  # returns nr of splits for majority class ('+', if inact_cnt > act_cnt, or '-' else)
  def nr_majority_splits
    @nr_majority_splits = @inact_act_ratio >= 1.5 ? @inact_act_ratio.ceil : ( @inact_act_ratio <= (2.0/3.0) ? -(1.0/@inact_act_ratio).ceil : ( @inact_act_ratio>1.0 ? 1 : -1) )
  end


  # shuffles and splits the majority array
  def majority_split
    res = []
    i=0
    if @nr_majority_splits.abs > 1
      split = @nr_majority_splits > 0 ? shuffle_split (@inact_hash.keys) : shuffle_split (@act_hash.keys)
      split.each do |a|
        res[i]={}
        a.each do |b|
          @nr_majority_splits > 0 ? res[i][b]=@inact_hash[b] : res[i][b]=@act_hash[b]
        end
        i+=1
      end
    end
    res
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
