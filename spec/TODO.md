# Ruby Spec Porting TODO

Source baseline: ../ruby_spec compared to local spec/

[ ] Missing spec
[-] Partial-passing spec (not byte-for-byte matching upstream spec)
[x] Fully-passing spec

## Specs
### command_line
- [x] command_line/backtrace_limit_spec.rb
- [x] command_line/dash_0_spec.rb
- [ ] command_line/dash_a_spec.rb
- [ ] command_line/dash_c_spec.rb
- [ ] command_line/dash_d_spec.rb
- [ ] command_line/dash_e_spec.rb
- [ ] command_line/dash_encoding_spec.rb
- [ ] command_line/dash_external_encoding_spec.rb
- [ ] command_line/dash_internal_encoding_spec.rb
- [ ] command_line/dash_l_spec.rb
- [ ] command_line/dash_n_spec.rb
- [ ] command_line/dash_p_spec.rb
- [ ] command_line/dash_r_spec.rb
- [ ] command_line/dash_s_spec.rb
- [ ] command_line/dash_upper_c_spec.rb
- [ ] command_line/dash_upper_e_spec.rb
- [ ] command_line/dash_upper_f_spec.rb
- [ ] command_line/dash_upper_i_spec.rb
- [ ] command_line/dash_upper_k_spec.rb
- [ ] command_line/dash_upper_s_spec.rb
- [ ] command_line/dash_upper_u_spec.rb
- [ ] command_line/dash_upper_w_spec.rb
- [ ] command_line/dash_upper_x_spec.rb
- [ ] command_line/dash_v_spec.rb
- [ ] command_line/dash_w_spec.rb
- [ ] command_line/dash_x_spec.rb
- [ ] command_line/error_message_spec.rb
- [ ] command_line/feature_spec.rb
- [ ] command_line/frozen_strings_spec.rb
- [ ] command_line/rubylib_spec.rb
- [ ] command_line/rubyopt_spec.rb
- [ ] command_line/syntax_error_spec.rb

### core/argf
- [ ] core/argf/argf_spec.rb
- [ ] core/argf/argv_spec.rb
- [ ] core/argf/binmode_spec.rb
- [ ] core/argf/close_spec.rb
- [ ] core/argf/closed_spec.rb
- [ ] core/argf/each_byte_spec.rb
- [ ] core/argf/each_char_spec.rb
- [ ] core/argf/each_codepoint_spec.rb
- [ ] core/argf/each_line_spec.rb
- [ ] core/argf/each_spec.rb
- [ ] core/argf/eof_spec.rb
- [ ] core/argf/file_spec.rb
- [ ] core/argf/filename_spec.rb
- [ ] core/argf/fileno_spec.rb
- [ ] core/argf/getc_spec.rb
- [ ] core/argf/gets_spec.rb
- [ ] core/argf/lineno_spec.rb
- [ ] core/argf/path_spec.rb
- [ ] core/argf/pos_spec.rb
- [ ] core/argf/read_nonblock_spec.rb
- [ ] core/argf/read_spec.rb
- [ ] core/argf/readchar_spec.rb
- [ ] core/argf/readline_spec.rb
- [ ] core/argf/readlines_spec.rb
- [ ] core/argf/readpartial_spec.rb
- [ ] core/argf/rewind_spec.rb
- [ ] core/argf/seek_spec.rb
- [ ] core/argf/set_encoding_spec.rb
- [ ] core/argf/skip_spec.rb
- [ ] core/argf/tell_spec.rb
- [ ] core/argf/to_a_spec.rb
- [ ] core/argf/to_i_spec.rb
- [ ] core/argf/to_io_spec.rb
- [ ] core/argf/to_s_spec.rb

### core/array
- [x] core/array/all_spec.rb
- [x] core/array/allocate_spec.rb
- [x] core/array/any_spec.rb
- [x] core/array/append_spec.rb
- [x] core/array/array_spec.rb
- [x] core/array/assoc_spec.rb
- [x] core/array/at_spec.rb
- [ ] core/array/bsearch_index_spec.rb
- [ ] core/array/bsearch_spec.rb
- [x] core/array/clear_spec.rb
- [x] core/array/clone_spec.rb
- [x] core/array/collect_spec.rb
- [ ] core/array/combination_spec.rb
- [ ] core/array/compact_spec.rb
- [x] core/array/comparison_spec.rb
- [x] core/array/concat_spec.rb
- [ ] core/array/constructor_spec.rb
- [ ] core/array/count_spec.rb
- [ ] core/array/cycle_spec.rb
- [ ] core/array/deconstruct_spec.rb
- [x] core/array/delete_at_spec.rb
- [ ] core/array/delete_if_spec.rb
- [ ] core/array/delete_spec.rb
- [ ] core/array/difference_spec.rb
- [x] core/array/dig_spec.rb
- [ ] core/array/drop_spec.rb
- [ ] core/array/drop_while_spec.rb
- [x] core/array/dup_spec.rb
- [ ] core/array/each_index_spec.rb
- [x] core/array/each_spec.rb
- [-] core/array/element_reference_spec.rb
- [ ] core/array/element_set_spec.rb
- [x] core/array/empty_spec.rb
- [x] core/array/eql_spec.rb
- [ ] core/array/equal_value_spec.rb
- [ ] core/array/fetch_spec.rb
- [ ] core/array/fetch_values_spec.rb
- [ ] core/array/fill_spec.rb
- [ ] core/array/filter_spec.rb
- [x] core/array/find_index_spec.rb
- [x] core/array/first_spec.rb
- [ ] core/array/flatten_spec.rb
- [ ] core/array/frozen_spec.rb
- [x] core/array/hash_spec.rb
- [x] core/array/include_spec.rb
- [x] core/array/index_spec.rb
- [x] core/array/initialize_spec.rb
- [ ] core/array/insert_spec.rb
- [x] core/array/inspect_spec.rb
- [ ] core/array/intersect_spec.rb
- [ ] core/array/intersection_spec.rb
- [x] core/array/join_spec.rb
- [ ] core/array/keep_if_spec.rb
- [x] core/array/last_spec.rb
- [x] core/array/length_spec.rb
- [x] core/array/map_spec.rb
- [ ] core/array/max_spec.rb
- [ ] core/array/min_spec.rb
- [ ] core/array/minmax_spec.rb
- [ ] core/array/minus_spec.rb
- [x] core/array/multiply_spec.rb
- [x] core/array/new_spec.rb
- [x] core/array/none_spec.rb
- [x] core/array/one_spec.rb

### core/array/pack
- [ ] core/array/pack/a_spec.rb
- [ ] core/array/pack/at_spec.rb
- [ ] core/array/pack/b_spec.rb
- [ ] core/array/pack/buffer_spec.rb
- [ ] core/array/pack/c_spec.rb
- [ ] core/array/pack/comment_spec.rb
- [ ] core/array/pack/d_spec.rb
- [ ] core/array/pack/e_spec.rb
- [ ] core/array/pack/empty_spec.rb
- [ ] core/array/pack/f_spec.rb
- [ ] core/array/pack/g_spec.rb
- [ ] core/array/pack/h_spec.rb
- [ ] core/array/pack/i_spec.rb
- [ ] core/array/pack/j_spec.rb
- [ ] core/array/pack/l_spec.rb
- [ ] core/array/pack/m_spec.rb
- [ ] core/array/pack/n_spec.rb
- [ ] core/array/pack/p_spec.rb
- [ ] core/array/pack/percent_spec.rb
- [ ] core/array/pack/q_spec.rb
- [ ] core/array/pack/s_spec.rb
- [ ] core/array/pack/u_spec.rb
- [ ] core/array/pack/v_spec.rb
- [ ] core/array/pack/w_spec.rb
- [ ] core/array/pack/x_spec.rb
- [ ] core/array/pack/z_spec.rb

### core/array
- [ ] core/array/partition_spec.rb
- [ ] core/array/permutation_spec.rb
- [x] core/array/plus_spec.rb
- [x] core/array/pop_spec.rb
- [x] core/array/prepend_spec.rb
- [ ] core/array/product_spec.rb
- [x] core/array/push_spec.rb
- [x] core/array/rassoc_spec.rb
- [ ] core/array/reject_spec.rb
- [ ] core/array/repeated_combination_spec.rb
- [ ] core/array/repeated_permutation_spec.rb
- [x] core/array/replace_spec.rb
- [ ] core/array/reverse_each_spec.rb
- [ ] core/array/reverse_spec.rb
- [ ] core/array/rindex_spec.rb
- [ ] core/array/rotate_spec.rb
- [ ] core/array/sample_spec.rb
- [x] core/array/select_spec.rb
- [x] core/array/shift_spec.rb
- [ ] core/array/shuffle_spec.rb
- [x] core/array/size_spec.rb
- [ ] core/array/slice_spec.rb
- [ ] core/array/sort_by_spec.rb
- [ ] core/array/sort_spec.rb
- [ ] core/array/sum_spec.rb
- [ ] core/array/take_spec.rb
- [ ] core/array/take_while_spec.rb
- [x] core/array/to_a_spec.rb
- [x] core/array/to_ary_spec.rb
- [ ] core/array/to_h_spec.rb
- [x] core/array/to_s_spec.rb
- [ ] core/array/transpose_spec.rb
- [ ] core/array/try_convert_spec.rb
- [ ] core/array/union_spec.rb
- [ ] core/array/uniq_spec.rb
- [x] core/array/unshift_spec.rb
- [ ] core/array/values_at_spec.rb
- [ ] core/array/zip_spec.rb

### core/basicobject
- [x] core/basicobject/__id__spec.rb
- [x] core/basicobject/__send___spec.rb
- [ ] core/basicobject/basicobject_spec.rb
- [x] core/basicobject/equal_spec.rb
- [x] core/basicobject/equal_value_spec.rb
- [x] core/basicobject/initialize_spec.rb
- [ ] core/basicobject/instance_eval_spec.rb
- [ ] core/basicobject/instance_exec_spec.rb
- [ ] core/basicobject/method_missing_spec.rb
- [x] core/basicobject/not_equal_spec.rb
- [x] core/basicobject/not_spec.rb
- [ ] core/basicobject/singleton_method_added_spec.rb
- [ ] core/basicobject/singleton_method_removed_spec.rb
- [ ] core/basicobject/singleton_method_undefined_spec.rb

### core/binding
- [ ] core/binding/clone_spec.rb
- [ ] core/binding/dup_spec.rb
- [ ] core/binding/eval_spec.rb
- [ ] core/binding/local_variable_defined_spec.rb
- [ ] core/binding/local_variable_get_spec.rb
- [ ] core/binding/local_variable_set_spec.rb
- [ ] core/binding/local_variables_spec.rb
- [ ] core/binding/receiver_spec.rb
- [ ] core/binding/source_location_spec.rb

### core/builtin_constants
- [ ] core/builtin_constants/builtin_constants_spec.rb

### core/class
- [ ] core/class/allocate_spec.rb
- [ ] core/class/attached_object_spec.rb
- [ ] core/class/dup_spec.rb
- [ ] core/class/inherited_spec.rb
- [ ] core/class/initialize_spec.rb
- [ ] core/class/new_spec.rb
- [ ] core/class/subclasses_spec.rb
- [ ] core/class/superclass_spec.rb

### core/comparable
- [ ] core/comparable/between_spec.rb
- [ ] core/comparable/clamp_spec.rb
- [ ] core/comparable/equal_value_spec.rb
- [ ] core/comparable/gt_spec.rb
- [ ] core/comparable/gte_spec.rb
- [ ] core/comparable/lt_spec.rb
- [ ] core/comparable/lte_spec.rb

### core/complex
- [ ] core/complex/abs2_spec.rb
- [ ] core/complex/abs_spec.rb
- [ ] core/complex/angle_spec.rb
- [ ] core/complex/arg_spec.rb
- [ ] core/complex/coerce_spec.rb
- [ ] core/complex/comparison_spec.rb
- [ ] core/complex/conj_spec.rb
- [ ] core/complex/conjugate_spec.rb
- [ ] core/complex/constants_spec.rb
- [ ] core/complex/denominator_spec.rb
- [ ] core/complex/divide_spec.rb
- [ ] core/complex/eql_spec.rb
- [ ] core/complex/equal_value_spec.rb
- [ ] core/complex/exponent_spec.rb
- [ ] core/complex/fdiv_spec.rb
- [ ] core/complex/finite_spec.rb
- [ ] core/complex/hash_spec.rb
- [ ] core/complex/imag_spec.rb
- [ ] core/complex/imaginary_spec.rb
- [ ] core/complex/infinite_spec.rb
- [ ] core/complex/inspect_spec.rb
- [ ] core/complex/integer_spec.rb
- [ ] core/complex/magnitude_spec.rb
- [ ] core/complex/marshal_dump_spec.rb
- [ ] core/complex/minus_spec.rb
- [ ] core/complex/multiply_spec.rb
- [ ] core/complex/negative_spec.rb
- [ ] core/complex/numerator_spec.rb
- [ ] core/complex/phase_spec.rb
- [ ] core/complex/plus_spec.rb
- [ ] core/complex/polar_spec.rb
- [ ] core/complex/positive_spec.rb
- [ ] core/complex/quo_spec.rb
- [ ] core/complex/rationalize_spec.rb
- [ ] core/complex/real_spec.rb
- [ ] core/complex/rect_spec.rb
- [ ] core/complex/rectangular_spec.rb
- [ ] core/complex/to_c_spec.rb
- [ ] core/complex/to_f_spec.rb
- [ ] core/complex/to_i_spec.rb
- [ ] core/complex/to_r_spec.rb
- [ ] core/complex/to_s_spec.rb
- [ ] core/complex/uminus_spec.rb

### core/conditionvariable
- [ ] core/conditionvariable/broadcast_spec.rb
- [ ] core/conditionvariable/marshal_dump_spec.rb
- [ ] core/conditionvariable/signal_spec.rb
- [ ] core/conditionvariable/wait_spec.rb

### core/data
- [ ] core/data/constants_spec.rb
- [ ] core/data/deconstruct_keys_spec.rb
- [ ] core/data/deconstruct_spec.rb
- [ ] core/data/define_spec.rb
- [ ] core/data/eql_spec.rb
- [ ] core/data/equal_value_spec.rb
- [ ] core/data/hash_spec.rb
- [ ] core/data/initialize_spec.rb
- [ ] core/data/inspect_spec.rb
- [ ] core/data/members_spec.rb
- [ ] core/data/to_h_spec.rb
- [ ] core/data/to_s_spec.rb
- [ ] core/data/with_spec.rb

### core/dir
- [ ] core/dir/chdir_spec.rb
- [ ] core/dir/children_spec.rb
- [ ] core/dir/chroot_spec.rb
- [ ] core/dir/close_spec.rb
- [ ] core/dir/delete_spec.rb
- [ ] core/dir/dir_spec.rb
- [ ] core/dir/each_child_spec.rb
- [ ] core/dir/each_spec.rb
- [ ] core/dir/element_reference_spec.rb
- [ ] core/dir/empty_spec.rb
- [ ] core/dir/entries_spec.rb
- [ ] core/dir/exist_spec.rb
- [ ] core/dir/fchdir_spec.rb
- [ ] core/dir/fileno_spec.rb
- [ ] core/dir/for_fd_spec.rb
- [ ] core/dir/foreach_spec.rb
- [ ] core/dir/getwd_spec.rb
- [ ] core/dir/glob_spec.rb
- [ ] core/dir/home_spec.rb
- [ ] core/dir/initialize_spec.rb
- [ ] core/dir/inspect_spec.rb
- [ ] core/dir/mkdir_spec.rb
- [ ] core/dir/open_spec.rb
- [ ] core/dir/path_spec.rb
- [ ] core/dir/pos_spec.rb
- [ ] core/dir/pwd_spec.rb
- [ ] core/dir/read_spec.rb
- [ ] core/dir/rewind_spec.rb
- [ ] core/dir/rmdir_spec.rb
- [ ] core/dir/seek_spec.rb
- [ ] core/dir/tell_spec.rb
- [ ] core/dir/to_path_spec.rb
- [ ] core/dir/unlink_spec.rb

### core/encoding
- [ ] core/encoding/_dump_spec.rb
- [ ] core/encoding/_load_spec.rb
- [ ] core/encoding/aliases_spec.rb
- [x] core/encoding/ascii_compatible_spec.rb
- [ ] core/encoding/compatible_spec.rb

### core/encoding/converter
- [ ] core/encoding/converter/asciicompat_encoding_spec.rb
- [ ] core/encoding/converter/constants_spec.rb
- [ ] core/encoding/converter/convert_spec.rb
- [ ] core/encoding/converter/convpath_spec.rb
- [ ] core/encoding/converter/destination_encoding_spec.rb
- [ ] core/encoding/converter/finish_spec.rb
- [ ] core/encoding/converter/insert_output_spec.rb
- [ ] core/encoding/converter/inspect_spec.rb
- [ ] core/encoding/converter/last_error_spec.rb
- [ ] core/encoding/converter/new_spec.rb
- [ ] core/encoding/converter/primitive_convert_spec.rb
- [ ] core/encoding/converter/primitive_errinfo_spec.rb
- [ ] core/encoding/converter/putback_spec.rb
- [ ] core/encoding/converter/replacement_spec.rb
- [ ] core/encoding/converter/search_convpath_spec.rb
- [ ] core/encoding/converter/source_encoding_spec.rb

### core/encoding
- [x] core/encoding/default_external_spec.rb
- [x] core/encoding/default_internal_spec.rb
- [ ] core/encoding/dummy_spec.rb
- [ ] core/encoding/find_spec.rb
- [x] core/encoding/inspect_spec.rb

### core/encoding/invalid_byte_sequence_error
- [ ] core/encoding/invalid_byte_sequence_error/destination_encoding_name_spec.rb
- [ ] core/encoding/invalid_byte_sequence_error/destination_encoding_spec.rb
- [ ] core/encoding/invalid_byte_sequence_error/error_bytes_spec.rb
- [ ] core/encoding/invalid_byte_sequence_error/incomplete_input_spec.rb
- [ ] core/encoding/invalid_byte_sequence_error/readagain_bytes_spec.rb
- [ ] core/encoding/invalid_byte_sequence_error/source_encoding_name_spec.rb
- [ ] core/encoding/invalid_byte_sequence_error/source_encoding_spec.rb

### core/encoding
- [ ] core/encoding/list_spec.rb
- [ ] core/encoding/locale_charmap_spec.rb
- [ ] core/encoding/name_list_spec.rb
- [x] core/encoding/name_spec.rb
- [ ] core/encoding/names_spec.rb
- [ ] core/encoding/replicate_spec.rb
- [x] core/encoding/to_s_spec.rb

### core/encoding/undefined_conversion_error
- [ ] core/encoding/undefined_conversion_error/destination_encoding_name_spec.rb
- [ ] core/encoding/undefined_conversion_error/destination_encoding_spec.rb
- [ ] core/encoding/undefined_conversion_error/error_char_spec.rb
- [ ] core/encoding/undefined_conversion_error/source_encoding_name_spec.rb
- [ ] core/encoding/undefined_conversion_error/source_encoding_spec.rb

### core/enumerable
- [ ] core/enumerable/all_spec.rb
- [ ] core/enumerable/any_spec.rb
- [ ] core/enumerable/chain_spec.rb
- [ ] core/enumerable/chunk_spec.rb
- [ ] core/enumerable/chunk_while_spec.rb
- [ ] core/enumerable/collect_concat_spec.rb
- [ ] core/enumerable/collect_spec.rb
- [ ] core/enumerable/compact_spec.rb
- [ ] core/enumerable/count_spec.rb
- [ ] core/enumerable/cycle_spec.rb
- [ ] core/enumerable/detect_spec.rb
- [ ] core/enumerable/drop_spec.rb
- [ ] core/enumerable/drop_while_spec.rb
- [ ] core/enumerable/each_cons_spec.rb
- [ ] core/enumerable/each_entry_spec.rb
- [ ] core/enumerable/each_slice_spec.rb
- [ ] core/enumerable/each_with_index_spec.rb
- [ ] core/enumerable/each_with_object_spec.rb
- [ ] core/enumerable/entries_spec.rb
- [ ] core/enumerable/filter_map_spec.rb
- [ ] core/enumerable/filter_spec.rb
- [ ] core/enumerable/find_all_spec.rb
- [ ] core/enumerable/find_index_spec.rb
- [ ] core/enumerable/find_spec.rb
- [ ] core/enumerable/first_spec.rb
- [ ] core/enumerable/flat_map_spec.rb
- [ ] core/enumerable/grep_spec.rb
- [ ] core/enumerable/grep_v_spec.rb
- [ ] core/enumerable/group_by_spec.rb
- [ ] core/enumerable/include_spec.rb
- [ ] core/enumerable/inject_spec.rb
- [ ] core/enumerable/lazy_spec.rb
- [ ] core/enumerable/map_spec.rb
- [ ] core/enumerable/max_by_spec.rb
- [ ] core/enumerable/max_spec.rb
- [ ] core/enumerable/member_spec.rb
- [ ] core/enumerable/min_by_spec.rb
- [ ] core/enumerable/min_spec.rb
- [ ] core/enumerable/minmax_by_spec.rb
- [ ] core/enumerable/minmax_spec.rb
- [ ] core/enumerable/none_spec.rb
- [ ] core/enumerable/one_spec.rb
- [ ] core/enumerable/partition_spec.rb
- [ ] core/enumerable/reduce_spec.rb
- [ ] core/enumerable/reject_spec.rb
- [ ] core/enumerable/reverse_each_spec.rb
- [ ] core/enumerable/select_spec.rb
- [ ] core/enumerable/slice_after_spec.rb
- [ ] core/enumerable/slice_before_spec.rb
- [ ] core/enumerable/slice_when_spec.rb
- [ ] core/enumerable/sort_by_spec.rb
- [ ] core/enumerable/sort_spec.rb
- [ ] core/enumerable/sum_spec.rb
- [ ] core/enumerable/take_spec.rb
- [ ] core/enumerable/take_while_spec.rb
- [ ] core/enumerable/tally_spec.rb
- [ ] core/enumerable/to_a_spec.rb
- [ ] core/enumerable/to_h_spec.rb
- [ ] core/enumerable/to_set_spec.rb
- [ ] core/enumerable/uniq_spec.rb
- [ ] core/enumerable/zip_spec.rb

### core/enumerator/arithmetic_sequence
- [ ] core/enumerator/arithmetic_sequence/begin_spec.rb
- [ ] core/enumerator/arithmetic_sequence/each_spec.rb
- [ ] core/enumerator/arithmetic_sequence/end_spec.rb
- [ ] core/enumerator/arithmetic_sequence/eq_spec.rb
- [ ] core/enumerator/arithmetic_sequence/exclude_end_spec.rb
- [ ] core/enumerator/arithmetic_sequence/first_spec.rb
- [ ] core/enumerator/arithmetic_sequence/hash_spec.rb
- [ ] core/enumerator/arithmetic_sequence/inspect_spec.rb
- [ ] core/enumerator/arithmetic_sequence/last_spec.rb
- [ ] core/enumerator/arithmetic_sequence/new_spec.rb
- [ ] core/enumerator/arithmetic_sequence/size_spec.rb
- [ ] core/enumerator/arithmetic_sequence/step_spec.rb

### core/enumerator/chain
- [ ] core/enumerator/chain/each_spec.rb
- [ ] core/enumerator/chain/initialize_spec.rb
- [ ] core/enumerator/chain/inspect_spec.rb
- [ ] core/enumerator/chain/rewind_spec.rb
- [ ] core/enumerator/chain/size_spec.rb

### core/enumerator
- [x] core/enumerator/each_spec.rb
- [ ] core/enumerator/each_with_index_spec.rb
- [ ] core/enumerator/each_with_object_spec.rb
- [x] core/enumerator/enum_for_spec.rb
- [ ] core/enumerator/enumerator_spec.rb
- [ ] core/enumerator/feed_spec.rb
- [ ] core/enumerator/first_spec.rb

### core/enumerator/generator
- [ ] core/enumerator/generator/each_spec.rb
- [ ] core/enumerator/generator/initialize_spec.rb

### core/enumerator
- [ ] core/enumerator/initialize_spec.rb
- [ ] core/enumerator/inspect_spec.rb

### core/enumerator/lazy
- [ ] core/enumerator/lazy/chunk_spec.rb
- [ ] core/enumerator/lazy/chunk_while_spec.rb
- [ ] core/enumerator/lazy/collect_concat_spec.rb
- [ ] core/enumerator/lazy/collect_spec.rb
- [ ] core/enumerator/lazy/compact_spec.rb
- [ ] core/enumerator/lazy/drop_spec.rb
- [ ] core/enumerator/lazy/drop_while_spec.rb
- [ ] core/enumerator/lazy/eager_spec.rb
- [ ] core/enumerator/lazy/enum_for_spec.rb
- [ ] core/enumerator/lazy/filter_map_spec.rb
- [ ] core/enumerator/lazy/filter_spec.rb
- [ ] core/enumerator/lazy/find_all_spec.rb
- [ ] core/enumerator/lazy/flat_map_spec.rb
- [ ] core/enumerator/lazy/force_spec.rb
- [ ] core/enumerator/lazy/grep_spec.rb
- [ ] core/enumerator/lazy/grep_v_spec.rb
- [ ] core/enumerator/lazy/initialize_spec.rb
- [ ] core/enumerator/lazy/lazy_spec.rb
- [ ] core/enumerator/lazy/map_spec.rb
- [ ] core/enumerator/lazy/reject_spec.rb
- [ ] core/enumerator/lazy/select_spec.rb
- [ ] core/enumerator/lazy/slice_after_spec.rb
- [ ] core/enumerator/lazy/slice_before_spec.rb
- [ ] core/enumerator/lazy/slice_when_spec.rb
- [ ] core/enumerator/lazy/take_spec.rb
- [ ] core/enumerator/lazy/take_while_spec.rb
- [ ] core/enumerator/lazy/to_enum_spec.rb
- [ ] core/enumerator/lazy/uniq_spec.rb
- [ ] core/enumerator/lazy/with_index_spec.rb
- [ ] core/enumerator/lazy/zip_spec.rb

### core/enumerator
- [ ] core/enumerator/new_spec.rb
- [ ] core/enumerator/next_spec.rb
- [x] core/enumerator/next_values_spec.rb
- [x] core/enumerator/peek_spec.rb
- [x] core/enumerator/peek_values_spec.rb
- [ ] core/enumerator/plus_spec.rb
- [ ] core/enumerator/produce_spec.rb

### core/enumerator/product
- [ ] core/enumerator/product/each_spec.rb
- [ ] core/enumerator/product/initialize_copy_spec.rb
- [ ] core/enumerator/product/initialize_spec.rb
- [ ] core/enumerator/product/inspect_spec.rb
- [ ] core/enumerator/product/rewind_spec.rb
- [ ] core/enumerator/product/size_spec.rb

### core/enumerator
- [ ] core/enumerator/product_spec.rb
- [ ] core/enumerator/rewind_spec.rb
- [ ] core/enumerator/size_spec.rb
- [x] core/enumerator/to_enum_spec.rb
- [ ] core/enumerator/with_index_spec.rb
- [ ] core/enumerator/with_object_spec.rb

### core/enumerator/yielder
- [ ] core/enumerator/yielder/append_spec.rb
- [ ] core/enumerator/yielder/initialize_spec.rb
- [ ] core/enumerator/yielder/to_proc_spec.rb
- [ ] core/enumerator/yielder/yield_spec.rb

### core/env
- [ ] core/env/assoc_spec.rb
- [ ] core/env/clear_spec.rb
- [ ] core/env/clone_spec.rb
- [ ] core/env/delete_if_spec.rb
- [ ] core/env/delete_spec.rb
- [ ] core/env/dup_spec.rb
- [ ] core/env/each_key_spec.rb
- [ ] core/env/each_pair_spec.rb
- [ ] core/env/each_spec.rb
- [ ] core/env/each_value_spec.rb
- [ ] core/env/element_reference_spec.rb
- [ ] core/env/element_set_spec.rb
- [ ] core/env/empty_spec.rb
- [ ] core/env/except_spec.rb
- [ ] core/env/fetch_spec.rb
- [ ] core/env/filter_spec.rb
- [ ] core/env/has_key_spec.rb
- [ ] core/env/has_value_spec.rb
- [ ] core/env/include_spec.rb
- [ ] core/env/inspect_spec.rb
- [ ] core/env/invert_spec.rb
- [ ] core/env/keep_if_spec.rb
- [ ] core/env/key_spec.rb
- [ ] core/env/keys_spec.rb
- [ ] core/env/length_spec.rb
- [ ] core/env/member_spec.rb
- [ ] core/env/merge_spec.rb
- [ ] core/env/rassoc_spec.rb
- [ ] core/env/rehash_spec.rb
- [ ] core/env/reject_spec.rb
- [ ] core/env/replace_spec.rb
- [ ] core/env/select_spec.rb
- [ ] core/env/shift_spec.rb
- [ ] core/env/size_spec.rb
- [ ] core/env/slice_spec.rb
- [ ] core/env/store_spec.rb
- [x] core/env/to_a_spec.rb
- [ ] core/env/to_h_spec.rb
- [ ] core/env/to_hash_spec.rb
- [ ] core/env/to_s_spec.rb
- [ ] core/env/update_spec.rb
- [ ] core/env/value_spec.rb
- [ ] core/env/values_at_spec.rb
- [ ] core/env/values_spec.rb

### core/exception
- [ ] core/exception/backtrace_locations_spec.rb
- [ ] core/exception/backtrace_spec.rb
- [ ] core/exception/case_compare_spec.rb
- [ ] core/exception/cause_spec.rb
- [ ] core/exception/detailed_message_spec.rb
- [ ] core/exception/dup_spec.rb
- [ ] core/exception/equal_value_spec.rb
- [ ] core/exception/errno_spec.rb
- [ ] core/exception/exception_spec.rb
- [ ] core/exception/exit_value_spec.rb
- [ ] core/exception/frozen_error_spec.rb
- [ ] core/exception/full_message_spec.rb
- [ ] core/exception/hierarchy_spec.rb
- [ ] core/exception/inspect_spec.rb
- [ ] core/exception/interrupt_spec.rb
- [ ] core/exception/io_error_spec.rb
- [ ] core/exception/key_error_spec.rb
- [ ] core/exception/load_error_spec.rb
- [ ] core/exception/message_spec.rb
- [ ] core/exception/name_error_spec.rb
- [ ] core/exception/name_spec.rb
- [ ] core/exception/new_spec.rb
- [ ] core/exception/no_method_error_spec.rb
- [ ] core/exception/reason_spec.rb
- [ ] core/exception/receiver_spec.rb
- [ ] core/exception/result_spec.rb
- [ ] core/exception/set_backtrace_spec.rb
- [ ] core/exception/signal_exception_spec.rb
- [ ] core/exception/signm_spec.rb
- [ ] core/exception/signo_spec.rb
- [ ] core/exception/standard_error_spec.rb
- [ ] core/exception/status_spec.rb
- [ ] core/exception/success_spec.rb
- [ ] core/exception/syntax_error_spec.rb
- [ ] core/exception/system_call_error_spec.rb
- [ ] core/exception/system_exit_spec.rb
- [ ] core/exception/to_s_spec.rb
- [ ] core/exception/top_level_spec.rb
- [ ] core/exception/uncaught_throw_error_spec.rb

### core/false
- [ ] core/false/and_spec.rb
- [ ] core/false/case_compare_spec.rb
- [ ] core/false/dup_spec.rb
- [ ] core/false/falseclass_spec.rb
- [x] core/false/inspect_spec.rb
- [ ] core/false/or_spec.rb
- [ ] core/false/singleton_method_spec.rb
- [x] core/false/to_s_spec.rb
- [ ] core/false/xor_spec.rb

### core/fiber
- [-] core/fiber/alive_spec.rb
- [ ] core/fiber/blocking_spec.rb
- [ ] core/fiber/current_spec.rb
- [ ] core/fiber/inspect_spec.rb
- [ ] core/fiber/kill_spec.rb
- [x] core/fiber/new_spec.rb
- [ ] core/fiber/raise_spec.rb
- [ ] core/fiber/resume_spec.rb
- [ ] core/fiber/scheduler_spec.rb
- [ ] core/fiber/set_scheduler_spec.rb
- [ ] core/fiber/storage_spec.rb
- [ ] core/fiber/transfer_spec.rb
- [x] core/fiber/yield_spec.rb

### core/file
- [ ] core/file/absolute_path_spec.rb
- [ ] core/file/atime_spec.rb
- [ ] core/file/basename_spec.rb
- [ ] core/file/birthtime_spec.rb
- [ ] core/file/blockdev_spec.rb
- [ ] core/file/chardev_spec.rb
- [ ] core/file/chmod_spec.rb
- [ ] core/file/chown_spec.rb

### core/file/constants
- [ ] core/file/constants/constants_spec.rb

### core/file
- [ ] core/file/constants_spec.rb
- [ ] core/file/ctime_spec.rb
- [ ] core/file/delete_spec.rb
- [ ] core/file/directory_spec.rb
- [ ] core/file/dirname_spec.rb
- [ ] core/file/empty_spec.rb
- [ ] core/file/executable_real_spec.rb
- [ ] core/file/executable_spec.rb
- [ ] core/file/exist_spec.rb
- [-] core/file/expand_path_spec.rb
- [ ] core/file/extname_spec.rb
- [ ] core/file/file_spec.rb
- [ ] core/file/flock_spec.rb
- [ ] core/file/fnmatch_spec.rb
- [ ] core/file/ftype_spec.rb
- [ ] core/file/grpowned_spec.rb
- [ ] core/file/identical_spec.rb
- [ ] core/file/initialize_spec.rb
- [ ] core/file/inspect_spec.rb
- [ ] core/file/join_spec.rb
- [ ] core/file/lchmod_spec.rb
- [ ] core/file/lchown_spec.rb
- [ ] core/file/link_spec.rb
- [ ] core/file/lstat_spec.rb
- [ ] core/file/lutime_spec.rb
- [ ] core/file/mkfifo_spec.rb
- [ ] core/file/mtime_spec.rb
- [ ] core/file/new_spec.rb
- [ ] core/file/null_spec.rb
- [ ] core/file/open_spec.rb
- [ ] core/file/owned_spec.rb
- [ ] core/file/path_spec.rb
- [ ] core/file/pipe_spec.rb
- [ ] core/file/printf_spec.rb
- [ ] core/file/read_spec.rb
- [ ] core/file/readable_real_spec.rb
- [ ] core/file/readable_spec.rb
- [ ] core/file/readlink_spec.rb
- [ ] core/file/realdirpath_spec.rb
- [ ] core/file/realpath_spec.rb
- [ ] core/file/rename_spec.rb
- [ ] core/file/reopen_spec.rb
- [ ] core/file/setgid_spec.rb
- [ ] core/file/setuid_spec.rb
- [ ] core/file/size_spec.rb
- [ ] core/file/socket_spec.rb
- [ ] core/file/split_spec.rb

### core/file/stat
- [ ] core/file/stat/atime_spec.rb
- [ ] core/file/stat/birthtime_spec.rb
- [ ] core/file/stat/blksize_spec.rb
- [ ] core/file/stat/blockdev_spec.rb
- [ ] core/file/stat/blocks_spec.rb
- [ ] core/file/stat/chardev_spec.rb
- [ ] core/file/stat/comparison_spec.rb
- [ ] core/file/stat/ctime_spec.rb
- [ ] core/file/stat/dev_major_spec.rb
- [ ] core/file/stat/dev_minor_spec.rb
- [ ] core/file/stat/dev_spec.rb
- [ ] core/file/stat/directory_spec.rb
- [ ] core/file/stat/executable_real_spec.rb
- [ ] core/file/stat/executable_spec.rb
- [ ] core/file/stat/file_spec.rb
- [ ] core/file/stat/ftype_spec.rb
- [ ] core/file/stat/gid_spec.rb
- [ ] core/file/stat/grpowned_spec.rb
- [ ] core/file/stat/ino_spec.rb
- [ ] core/file/stat/inspect_spec.rb
- [ ] core/file/stat/mode_spec.rb
- [ ] core/file/stat/mtime_spec.rb
- [ ] core/file/stat/new_spec.rb
- [ ] core/file/stat/nlink_spec.rb
- [ ] core/file/stat/owned_spec.rb
- [ ] core/file/stat/pipe_spec.rb
- [ ] core/file/stat/rdev_major_spec.rb
- [ ] core/file/stat/rdev_minor_spec.rb
- [ ] core/file/stat/rdev_spec.rb
- [ ] core/file/stat/readable_real_spec.rb
- [ ] core/file/stat/readable_spec.rb
- [ ] core/file/stat/setgid_spec.rb
- [ ] core/file/stat/setuid_spec.rb
- [ ] core/file/stat/size_spec.rb
- [ ] core/file/stat/socket_spec.rb
- [ ] core/file/stat/sticky_spec.rb
- [ ] core/file/stat/symlink_spec.rb
- [ ] core/file/stat/uid_spec.rb
- [ ] core/file/stat/world_readable_spec.rb
- [ ] core/file/stat/world_writable_spec.rb
- [ ] core/file/stat/writable_real_spec.rb
- [ ] core/file/stat/writable_spec.rb
- [ ] core/file/stat/zero_spec.rb

### core/file
- [ ] core/file/stat_spec.rb
- [ ] core/file/sticky_spec.rb
- [ ] core/file/symlink_spec.rb
- [ ] core/file/to_path_spec.rb
- [ ] core/file/truncate_spec.rb
- [ ] core/file/umask_spec.rb
- [ ] core/file/unlink_spec.rb
- [ ] core/file/utime_spec.rb
- [ ] core/file/world_readable_spec.rb
- [ ] core/file/world_writable_spec.rb
- [ ] core/file/writable_real_spec.rb
- [ ] core/file/writable_spec.rb
- [ ] core/file/zero_spec.rb

### core/filetest
- [ ] core/filetest/blockdev_spec.rb
- [ ] core/filetest/chardev_spec.rb
- [ ] core/filetest/directory_spec.rb
- [ ] core/filetest/executable_real_spec.rb
- [ ] core/filetest/executable_spec.rb
- [ ] core/filetest/exist_spec.rb
- [ ] core/filetest/file_spec.rb
- [ ] core/filetest/grpowned_spec.rb
- [ ] core/filetest/identical_spec.rb
- [ ] core/filetest/owned_spec.rb
- [ ] core/filetest/pipe_spec.rb
- [ ] core/filetest/readable_real_spec.rb
- [ ] core/filetest/readable_spec.rb
- [ ] core/filetest/setgid_spec.rb
- [ ] core/filetest/setuid_spec.rb
- [ ] core/filetest/size_spec.rb
- [ ] core/filetest/socket_spec.rb
- [ ] core/filetest/sticky_spec.rb
- [ ] core/filetest/symlink_spec.rb
- [ ] core/filetest/world_readable_spec.rb
- [ ] core/filetest/world_writable_spec.rb
- [ ] core/filetest/writable_real_spec.rb
- [ ] core/filetest/writable_spec.rb
- [ ] core/filetest/zero_spec.rb

### core/float
- [ ] core/float/abs_spec.rb
- [ ] core/float/angle_spec.rb
- [ ] core/float/arg_spec.rb
- [ ] core/float/case_compare_spec.rb
- [ ] core/float/ceil_spec.rb
- [ ] core/float/coerce_spec.rb
- [ ] core/float/comparison_spec.rb
- [ ] core/float/constants_spec.rb
- [ ] core/float/denominator_spec.rb
- [ ] core/float/divide_spec.rb
- [ ] core/float/divmod_spec.rb
- [ ] core/float/dup_spec.rb
- [ ] core/float/eql_spec.rb
- [ ] core/float/equal_value_spec.rb
- [ ] core/float/exponent_spec.rb
- [ ] core/float/fdiv_spec.rb
- [ ] core/float/finite_spec.rb
- [ ] core/float/float_spec.rb
- [ ] core/float/floor_spec.rb
- [ ] core/float/gt_spec.rb
- [ ] core/float/gte_spec.rb
- [ ] core/float/hash_spec.rb
- [x] core/float/infinite_spec.rb
- [x] core/float/inspect_spec.rb
- [ ] core/float/lt_spec.rb
- [ ] core/float/lte_spec.rb
- [ ] core/float/magnitude_spec.rb
- [ ] core/float/minus_spec.rb
- [ ] core/float/modulo_spec.rb
- [ ] core/float/multiply_spec.rb
- [x] core/float/nan_spec.rb
- [ ] core/float/negative_spec.rb
- [ ] core/float/next_float_spec.rb
- [ ] core/float/numerator_spec.rb
- [ ] core/float/phase_spec.rb
- [ ] core/float/plus_spec.rb
- [ ] core/float/positive_spec.rb
- [ ] core/float/prev_float_spec.rb
- [ ] core/float/quo_spec.rb
- [ ] core/float/rationalize_spec.rb
- [ ] core/float/round_spec.rb
- [ ] core/float/to_f_spec.rb
- [ ] core/float/to_i_spec.rb
- [ ] core/float/to_int_spec.rb
- [ ] core/float/to_r_spec.rb
- [x] core/float/to_s_spec.rb
- [ ] core/float/truncate_spec.rb
- [ ] core/float/uminus_spec.rb
- [ ] core/float/uplus_spec.rb
- [ ] core/float/zero_spec.rb

### core/gc
- [ ] core/gc/auto_compact_spec.rb
- [ ] core/gc/config_spec.rb
- [ ] core/gc/count_spec.rb
- [ ] core/gc/disable_spec.rb
- [ ] core/gc/enable_spec.rb
- [ ] core/gc/garbage_collect_spec.rb
- [ ] core/gc/measure_total_time_spec.rb

### core/gc/profiler
- [ ] core/gc/profiler/clear_spec.rb
- [ ] core/gc/profiler/disable_spec.rb
- [ ] core/gc/profiler/enable_spec.rb
- [ ] core/gc/profiler/enabled_spec.rb
- [ ] core/gc/profiler/report_spec.rb
- [ ] core/gc/profiler/result_spec.rb
- [ ] core/gc/profiler/total_time_spec.rb

### core/gc
- [ ] core/gc/start_spec.rb
- [ ] core/gc/stat_spec.rb
- [ ] core/gc/stress_spec.rb
- [ ] core/gc/total_time_spec.rb

### core/hash
- [x] core/hash/allocate_spec.rb
- [ ] core/hash/any_spec.rb
- [ ] core/hash/assoc_spec.rb
- [ ] core/hash/clear_spec.rb
- [ ] core/hash/clone_spec.rb
- [ ] core/hash/compact_spec.rb
- [ ] core/hash/compare_by_identity_spec.rb
- [ ] core/hash/constructor_spec.rb
- [ ] core/hash/deconstruct_keys_spec.rb
- [x] core/hash/default_proc_spec.rb
- [x] core/hash/default_spec.rb
- [ ] core/hash/delete_if_spec.rb
- [x] core/hash/delete_spec.rb
- [x] core/hash/dig_spec.rb
- [ ] core/hash/each_key_spec.rb
- [x] core/hash/each_pair_spec.rb
- [x] core/hash/each_spec.rb
- [ ] core/hash/each_value_spec.rb
- [x] core/hash/element_reference_spec.rb
- [x] core/hash/element_set_spec.rb
- [x] core/hash/empty_spec.rb
- [ ] core/hash/eql_spec.rb
- [ ] core/hash/equal_value_spec.rb
- [ ] core/hash/except_spec.rb
- [x] core/hash/fetch_spec.rb
- [ ] core/hash/fetch_values_spec.rb
- [ ] core/hash/filter_spec.rb
- [ ] core/hash/flatten_spec.rb
- [ ] core/hash/gt_spec.rb
- [ ] core/hash/gte_spec.rb
- [x] core/hash/has_key_spec.rb
- [ ] core/hash/has_value_spec.rb
- [ ] core/hash/hash_spec.rb
- [x] core/hash/include_spec.rb
- [x] core/hash/initialize_spec.rb
- [-] core/hash/inspect_spec.rb
- [ ] core/hash/invert_spec.rb
- [ ] core/hash/keep_if_spec.rb
- [x] core/hash/key_spec.rb
- [x] core/hash/keys_spec.rb
- [x] core/hash/length_spec.rb
- [ ] core/hash/lt_spec.rb
- [ ] core/hash/lte_spec.rb
- [x] core/hash/member_spec.rb
- [ ] core/hash/merge_spec.rb
- [ ] core/hash/new_spec.rb
- [ ] core/hash/rassoc_spec.rb
- [ ] core/hash/rehash_spec.rb
- [ ] core/hash/reject_spec.rb
- [ ] core/hash/replace_spec.rb
- [ ] core/hash/ruby2_keywords_hash_spec.rb
- [ ] core/hash/select_spec.rb
- [ ] core/hash/shift_spec.rb
- [x] core/hash/size_spec.rb
- [ ] core/hash/slice_spec.rb
- [ ] core/hash/sort_spec.rb
- [ ] core/hash/store_spec.rb
- [x] core/hash/to_a_spec.rb
- [ ] core/hash/to_h_spec.rb
- [ ] core/hash/to_hash_spec.rb
- [ ] core/hash/to_proc_spec.rb
- [x] core/hash/to_s_spec.rb
- [ ] core/hash/transform_keys_spec.rb
- [ ] core/hash/transform_values_spec.rb
- [ ] core/hash/try_convert_spec.rb
- [ ] core/hash/update_spec.rb
- [ ] core/hash/value_spec.rb
- [ ] core/hash/values_at_spec.rb
- [x] core/hash/values_spec.rb

### core/integer
- [x] core/integer/abs_spec.rb
- [ ] core/integer/allbits_spec.rb
- [ ] core/integer/anybits_spec.rb
- [ ] core/integer/bit_and_spec.rb
- [ ] core/integer/bit_length_spec.rb
- [ ] core/integer/bit_or_spec.rb
- [ ] core/integer/bit_xor_spec.rb
- [x] core/integer/case_compare_spec.rb
- [ ] core/integer/ceil_spec.rb
- [ ] core/integer/ceildiv_spec.rb
- [x] core/integer/chr_spec.rb
- [ ] core/integer/coerce_spec.rb
- [ ] core/integer/comparison_spec.rb
- [ ] core/integer/complement_spec.rb
- [ ] core/integer/constants_spec.rb
- [x] core/integer/denominator_spec.rb
- [ ] core/integer/digits_spec.rb
- [ ] core/integer/div_spec.rb
- [ ] core/integer/divide_spec.rb
- [ ] core/integer/divmod_spec.rb
- [x] core/integer/downto_spec.rb
- [ ] core/integer/dup_spec.rb
- [ ] core/integer/element_reference_spec.rb
- [ ] core/integer/equal_value_spec.rb
- [x] core/integer/even_spec.rb
- [ ] core/integer/exponent_spec.rb
- [ ] core/integer/fdiv_spec.rb
- [ ] core/integer/floor_spec.rb
- [ ] core/integer/gcd_spec.rb
- [ ] core/integer/gcdlcm_spec.rb
- [x] core/integer/gt_spec.rb
- [x] core/integer/gte_spec.rb
- [ ] core/integer/integer_spec.rb
- [ ] core/integer/lcm_spec.rb
- [ ] core/integer/left_shift_spec.rb
- [ ] core/integer/lt_spec.rb
- [ ] core/integer/lte_spec.rb
- [ ] core/integer/magnitude_spec.rb
- [x] core/integer/minus_spec.rb
- [ ] core/integer/modulo_spec.rb
- [x] core/integer/multiply_spec.rb
- [x] core/integer/next_spec.rb
- [ ] core/integer/nobits_spec.rb
- [ ] core/integer/numerator_spec.rb
- [x] core/integer/odd_spec.rb
- [x] core/integer/ord_spec.rb
- [x] core/integer/plus_spec.rb
- [ ] core/integer/pow_spec.rb
- [x] core/integer/pred_spec.rb
- [ ] core/integer/rationalize_spec.rb
- [ ] core/integer/remainder_spec.rb
- [ ] core/integer/right_shift_spec.rb
- [ ] core/integer/round_spec.rb
- [x] core/integer/size_spec.rb
- [ ] core/integer/sqrt_spec.rb
- [x] core/integer/succ_spec.rb
- [x] core/integer/times_spec.rb
- [x] core/integer/to_f_spec.rb
- [x] core/integer/to_i_spec.rb
- [x] core/integer/to_int_spec.rb
- [ ] core/integer/to_r_spec.rb
- [x] core/integer/to_s_spec.rb
- [x] core/integer/truncate_spec.rb
- [x] core/integer/try_convert_spec.rb
- [x] core/integer/uminus_spec.rb
- [x] core/integer/upto_spec.rb
- [x] core/integer/zero_spec.rb

### core/io
- [ ] core/io/advise_spec.rb
- [ ] core/io/autoclose_spec.rb
- [ ] core/io/binmode_spec.rb
- [ ] core/io/binread_spec.rb
- [ ] core/io/binwrite_spec.rb

### core/io/buffer
- [ ] core/io/buffer/and_spec.rb
- [ ] core/io/buffer/empty_spec.rb
- [ ] core/io/buffer/external_spec.rb
- [ ] core/io/buffer/for_spec.rb
- [ ] core/io/buffer/free_spec.rb
- [ ] core/io/buffer/initialize_spec.rb
- [ ] core/io/buffer/internal_spec.rb
- [ ] core/io/buffer/locked_spec.rb
- [ ] core/io/buffer/map_spec.rb
- [ ] core/io/buffer/mapped_spec.rb
- [ ] core/io/buffer/not_spec.rb
- [ ] core/io/buffer/null_spec.rb
- [ ] core/io/buffer/or_spec.rb
- [ ] core/io/buffer/private_spec.rb
- [ ] core/io/buffer/readonly_spec.rb
- [ ] core/io/buffer/resize_spec.rb
- [ ] core/io/buffer/shared_spec.rb
- [ ] core/io/buffer/string_spec.rb
- [ ] core/io/buffer/transfer_spec.rb
- [ ] core/io/buffer/valid_spec.rb
- [ ] core/io/buffer/xor_spec.rb

### core/io
- [ ] core/io/close_on_exec_spec.rb
- [ ] core/io/close_read_spec.rb
- [ ] core/io/close_spec.rb
- [ ] core/io/close_write_spec.rb
- [ ] core/io/closed_spec.rb
- [ ] core/io/constants_spec.rb
- [ ] core/io/copy_stream_spec.rb
- [ ] core/io/dup_spec.rb
- [ ] core/io/each_byte_spec.rb
- [ ] core/io/each_char_spec.rb
- [ ] core/io/each_codepoint_spec.rb
- [ ] core/io/each_line_spec.rb
- [ ] core/io/each_spec.rb
- [ ] core/io/eof_spec.rb
- [ ] core/io/external_encoding_spec.rb
- [ ] core/io/fcntl_spec.rb
- [ ] core/io/fdatasync_spec.rb
- [ ] core/io/fileno_spec.rb
- [ ] core/io/flush_spec.rb
- [ ] core/io/for_fd_spec.rb
- [ ] core/io/foreach_spec.rb
- [ ] core/io/fsync_spec.rb
- [ ] core/io/getbyte_spec.rb
- [ ] core/io/getc_spec.rb
- [ ] core/io/gets_spec.rb
- [ ] core/io/initialize_spec.rb
- [ ] core/io/inspect_spec.rb
- [ ] core/io/internal_encoding_spec.rb
- [ ] core/io/io_spec.rb
- [ ] core/io/ioctl_spec.rb
- [ ] core/io/isatty_spec.rb
- [ ] core/io/lineno_spec.rb
- [ ] core/io/new_spec.rb
- [ ] core/io/nonblock_spec.rb
- [ ] core/io/open_spec.rb
- [ ] core/io/output_spec.rb
- [ ] core/io/path_spec.rb
- [ ] core/io/pid_spec.rb
- [ ] core/io/pipe_spec.rb
- [ ] core/io/popen_spec.rb
- [ ] core/io/pos_spec.rb
- [ ] core/io/pread_spec.rb
- [ ] core/io/print_spec.rb
- [ ] core/io/printf_spec.rb
- [ ] core/io/putc_spec.rb
- [ ] core/io/puts_spec.rb
- [ ] core/io/pwrite_spec.rb
- [ ] core/io/read_nonblock_spec.rb
- [ ] core/io/read_spec.rb
- [ ] core/io/readbyte_spec.rb
- [ ] core/io/readchar_spec.rb
- [ ] core/io/readline_spec.rb
- [ ] core/io/readlines_spec.rb
- [ ] core/io/readpartial_spec.rb
- [ ] core/io/reopen_spec.rb
- [ ] core/io/rewind_spec.rb
- [ ] core/io/seek_spec.rb
- [ ] core/io/select_spec.rb
- [ ] core/io/set_encoding_by_bom_spec.rb
- [ ] core/io/set_encoding_spec.rb
- [ ] core/io/stat_spec.rb
- [ ] core/io/sync_spec.rb
- [ ] core/io/sysopen_spec.rb
- [ ] core/io/sysread_spec.rb
- [ ] core/io/sysseek_spec.rb
- [ ] core/io/syswrite_spec.rb
- [ ] core/io/tell_spec.rb
- [ ] core/io/to_i_spec.rb
- [ ] core/io/to_io_spec.rb
- [ ] core/io/try_convert_spec.rb
- [ ] core/io/tty_spec.rb
- [ ] core/io/ungetbyte_spec.rb
- [ ] core/io/ungetc_spec.rb
- [ ] core/io/write_nonblock_spec.rb
- [ ] core/io/write_spec.rb

### core/kernel
- [ ] core/kernel/Array_spec.rb
- [ ] core/kernel/Complex_spec.rb
- [ ] core/kernel/Float_spec.rb
- [ ] core/kernel/Hash_spec.rb
- [ ] core/kernel/Integer_spec.rb
- [ ] core/kernel/Rational_spec.rb
- [ ] core/kernel/String_spec.rb
- [ ] core/kernel/__callee___spec.rb
- [x] core/kernel/__dir___spec.rb
- [ ] core/kernel/__method___spec.rb
- [ ] core/kernel/abort_spec.rb
- [ ] core/kernel/at_exit_spec.rb
- [ ] core/kernel/autoload_spec.rb
- [ ] core/kernel/backtick_spec.rb
- [ ] core/kernel/binding_spec.rb
- [ ] core/kernel/block_given_spec.rb
- [ ] core/kernel/caller_locations_spec.rb
- [ ] core/kernel/caller_spec.rb
- [ ] core/kernel/case_compare_spec.rb
- [ ] core/kernel/catch_spec.rb
- [ ] core/kernel/chomp_spec.rb
- [ ] core/kernel/chop_spec.rb
- [ ] core/kernel/class_spec.rb
- [ ] core/kernel/clone_spec.rb
- [ ] core/kernel/comparison_spec.rb
- [ ] core/kernel/define_singleton_method_spec.rb
- [ ] core/kernel/display_spec.rb
- [ ] core/kernel/dup_spec.rb
- [x] core/kernel/enum_for_spec.rb
- [ ] core/kernel/eql_spec.rb
- [ ] core/kernel/equal_value_spec.rb
- [ ] core/kernel/eval_spec.rb
- [ ] core/kernel/exec_spec.rb
- [ ] core/kernel/exit_spec.rb
- [ ] core/kernel/extend_spec.rb
- [ ] core/kernel/fail_spec.rb
- [ ] core/kernel/fork_spec.rb
- [ ] core/kernel/format_spec.rb
- [ ] core/kernel/freeze_spec.rb
- [ ] core/kernel/frozen_spec.rb
- [ ] core/kernel/gets_spec.rb
- [ ] core/kernel/global_variables_spec.rb
- [ ] core/kernel/gsub_spec.rb
- [ ] core/kernel/initialize_clone_spec.rb
- [ ] core/kernel/initialize_copy_spec.rb
- [ ] core/kernel/initialize_dup_spec.rb
- [ ] core/kernel/inspect_spec.rb
- [ ] core/kernel/instance_of_spec.rb
- [ ] core/kernel/instance_variable_defined_spec.rb
- [ ] core/kernel/instance_variable_get_spec.rb
- [ ] core/kernel/instance_variable_set_spec.rb
- [ ] core/kernel/instance_variables_spec.rb
- [ ] core/kernel/is_a_spec.rb
- [ ] core/kernel/itself_spec.rb
- [ ] core/kernel/kind_of_spec.rb
- [ ] core/kernel/lambda_spec.rb
- [ ] core/kernel/load_spec.rb
- [ ] core/kernel/local_variables_spec.rb
- [ ] core/kernel/loop_spec.rb
- [ ] core/kernel/match_spec.rb
- [ ] core/kernel/method_spec.rb
- [ ] core/kernel/methods_spec.rb
- [x] core/kernel/nil_spec.rb
- [ ] core/kernel/not_match_spec.rb
- [ ] core/kernel/object_id_spec.rb
- [ ] core/kernel/open_spec.rb
- [ ] core/kernel/p_spec.rb
- [ ] core/kernel/pp_spec.rb
- [ ] core/kernel/print_spec.rb
- [ ] core/kernel/printf_spec.rb
- [ ] core/kernel/private_methods_spec.rb
- [ ] core/kernel/proc_spec.rb
- [ ] core/kernel/protected_methods_spec.rb
- [ ] core/kernel/public_method_spec.rb
- [ ] core/kernel/public_methods_spec.rb
- [ ] core/kernel/public_send_spec.rb
- [ ] core/kernel/putc_spec.rb
- [ ] core/kernel/puts_spec.rb
- [ ] core/kernel/raise_spec.rb
- [ ] core/kernel/rand_spec.rb
- [ ] core/kernel/readline_spec.rb
- [ ] core/kernel/readlines_spec.rb
- [ ] core/kernel/remove_instance_variable_spec.rb
- [ ] core/kernel/require_relative_spec.rb
- [ ] core/kernel/require_spec.rb
- [ ] core/kernel/respond_to_missing_spec.rb
- [x] core/kernel/respond_to_spec.rb
- [ ] core/kernel/select_spec.rb
- [ ] core/kernel/send_spec.rb
- [ ] core/kernel/set_trace_func_spec.rb
- [ ] core/kernel/singleton_class_spec.rb
- [ ] core/kernel/singleton_method_spec.rb
- [ ] core/kernel/singleton_methods_spec.rb
- [ ] core/kernel/sleep_spec.rb
- [ ] core/kernel/spawn_spec.rb
- [ ] core/kernel/sprintf_spec.rb
- [ ] core/kernel/srand_spec.rb
- [ ] core/kernel/sub_spec.rb
- [ ] core/kernel/syscall_spec.rb
- [ ] core/kernel/system_spec.rb
- [ ] core/kernel/taint_spec.rb
- [ ] core/kernel/tainted_spec.rb
- [-] core/kernel/tap_spec.rb
- [ ] core/kernel/test_spec.rb
- [ ] core/kernel/then_spec.rb
- [ ] core/kernel/throw_spec.rb
- [x] core/kernel/to_enum_spec.rb
- [ ] core/kernel/to_s_spec.rb
- [ ] core/kernel/trace_var_spec.rb
- [ ] core/kernel/trap_spec.rb
- [ ] core/kernel/trust_spec.rb
- [ ] core/kernel/untaint_spec.rb
- [ ] core/kernel/untrace_var_spec.rb
- [ ] core/kernel/untrust_spec.rb
- [ ] core/kernel/untrusted_spec.rb
- [ ] core/kernel/warn_spec.rb
- [ ] core/kernel/yield_self_spec.rb

### core/main
- [ ] core/main/define_method_spec.rb
- [ ] core/main/include_spec.rb
- [ ] core/main/private_spec.rb
- [ ] core/main/public_spec.rb
- [ ] core/main/ruby2_keywords_spec.rb
- [ ] core/main/to_s_spec.rb
- [ ] core/main/using_spec.rb

### core/marshal
- [ ] core/marshal/dump_spec.rb
- [ ] core/marshal/float_spec.rb
- [ ] core/marshal/load_spec.rb
- [ ] core/marshal/major_version_spec.rb
- [ ] core/marshal/minor_version_spec.rb
- [ ] core/marshal/restore_spec.rb

### core/matchdata
- [ ] core/matchdata/allocate_spec.rb
- [ ] core/matchdata/begin_spec.rb
- [ ] core/matchdata/bytebegin_spec.rb
- [ ] core/matchdata/byteend_spec.rb
- [ ] core/matchdata/byteoffset_spec.rb
- [ ] core/matchdata/captures_spec.rb
- [ ] core/matchdata/deconstruct_keys_spec.rb
- [ ] core/matchdata/deconstruct_spec.rb
- [ ] core/matchdata/dup_spec.rb
- [ ] core/matchdata/element_reference_spec.rb
- [ ] core/matchdata/end_spec.rb
- [ ] core/matchdata/eql_spec.rb
- [ ] core/matchdata/equal_value_spec.rb
- [ ] core/matchdata/hash_spec.rb
- [ ] core/matchdata/inspect_spec.rb
- [ ] core/matchdata/length_spec.rb
- [ ] core/matchdata/match_length_spec.rb
- [ ] core/matchdata/match_spec.rb
- [ ] core/matchdata/named_captures_spec.rb
- [ ] core/matchdata/names_spec.rb
- [ ] core/matchdata/offset_spec.rb
- [ ] core/matchdata/post_match_spec.rb
- [ ] core/matchdata/pre_match_spec.rb
- [ ] core/matchdata/regexp_spec.rb
- [ ] core/matchdata/size_spec.rb
- [ ] core/matchdata/string_spec.rb
- [ ] core/matchdata/to_a_spec.rb
- [ ] core/matchdata/to_s_spec.rb
- [ ] core/matchdata/values_at_spec.rb

### core/math
- [ ] core/math/acos_spec.rb
- [ ] core/math/acosh_spec.rb
- [ ] core/math/asin_spec.rb
- [ ] core/math/asinh_spec.rb
- [ ] core/math/atan2_spec.rb
- [ ] core/math/atan_spec.rb
- [ ] core/math/atanh_spec.rb
- [ ] core/math/cbrt_spec.rb
- [ ] core/math/constants_spec.rb
- [ ] core/math/cos_spec.rb
- [ ] core/math/cosh_spec.rb
- [ ] core/math/erf_spec.rb
- [ ] core/math/erfc_spec.rb
- [ ] core/math/exp_spec.rb
- [ ] core/math/expm1_spec.rb
- [ ] core/math/frexp_spec.rb
- [ ] core/math/gamma_spec.rb
- [ ] core/math/hypot_spec.rb
- [ ] core/math/ldexp_spec.rb
- [ ] core/math/lgamma_spec.rb
- [ ] core/math/log10_spec.rb
- [ ] core/math/log1p_spec.rb
- [ ] core/math/log2_spec.rb
- [ ] core/math/log_spec.rb
- [ ] core/math/sin_spec.rb
- [ ] core/math/sinh_spec.rb
- [ ] core/math/sqrt_spec.rb
- [ ] core/math/tan_spec.rb
- [ ] core/math/tanh_spec.rb

### core/method
- [ ] core/method/arity_spec.rb
- [ ] core/method/call_spec.rb
- [ ] core/method/case_compare_spec.rb
- [ ] core/method/clone_spec.rb
- [ ] core/method/compose_spec.rb
- [ ] core/method/curry_spec.rb
- [ ] core/method/dup_spec.rb
- [ ] core/method/element_reference_spec.rb
- [ ] core/method/eql_spec.rb
- [ ] core/method/equal_value_spec.rb
- [ ] core/method/hash_spec.rb
- [ ] core/method/inspect_spec.rb
- [ ] core/method/name_spec.rb
- [ ] core/method/original_name_spec.rb
- [ ] core/method/owner_spec.rb
- [ ] core/method/parameters_spec.rb
- [ ] core/method/private_spec.rb
- [ ] core/method/protected_spec.rb
- [ ] core/method/public_spec.rb
- [ ] core/method/receiver_spec.rb
- [ ] core/method/source_location_spec.rb
- [ ] core/method/super_method_spec.rb
- [ ] core/method/to_proc_spec.rb
- [ ] core/method/to_s_spec.rb
- [ ] core/method/unbind_spec.rb

### core/module
- [ ] core/module/alias_method_spec.rb
- [ ] core/module/ancestors_spec.rb
- [ ] core/module/append_features_spec.rb
- [ ] core/module/attr_accessor_spec.rb
- [ ] core/module/attr_reader_spec.rb
- [ ] core/module/attr_spec.rb
- [ ] core/module/attr_writer_spec.rb
- [ ] core/module/autoload_spec.rb
- [ ] core/module/case_compare_spec.rb
- [ ] core/module/class_eval_spec.rb
- [ ] core/module/class_exec_spec.rb
- [ ] core/module/class_variable_defined_spec.rb
- [ ] core/module/class_variable_get_spec.rb
- [ ] core/module/class_variable_set_spec.rb
- [ ] core/module/class_variables_spec.rb
- [ ] core/module/comparison_spec.rb
- [ ] core/module/const_added_spec.rb
- [ ] core/module/const_defined_spec.rb
- [ ] core/module/const_get_spec.rb
- [ ] core/module/const_missing_spec.rb
- [ ] core/module/const_set_spec.rb
- [ ] core/module/const_source_location_spec.rb
- [ ] core/module/constants_spec.rb
- [ ] core/module/define_method_spec.rb
- [ ] core/module/define_singleton_method_spec.rb
- [ ] core/module/deprecate_constant_spec.rb
- [ ] core/module/eql_spec.rb
- [ ] core/module/equal_spec.rb
- [ ] core/module/equal_value_spec.rb
- [ ] core/module/extend_object_spec.rb
- [ ] core/module/extended_spec.rb
- [ ] core/module/freeze_spec.rb
- [ ] core/module/gt_spec.rb
- [ ] core/module/gte_spec.rb
- [ ] core/module/include_spec.rb
- [ ] core/module/included_modules_spec.rb
- [ ] core/module/included_spec.rb
- [ ] core/module/initialize_copy_spec.rb
- [ ] core/module/initialize_spec.rb
- [ ] core/module/instance_method_spec.rb
- [ ] core/module/instance_methods_spec.rb
- [ ] core/module/lt_spec.rb
- [ ] core/module/lte_spec.rb
- [ ] core/module/method_added_spec.rb
- [ ] core/module/method_defined_spec.rb
- [ ] core/module/method_removed_spec.rb
- [ ] core/module/method_undefined_spec.rb
- [ ] core/module/module_eval_spec.rb
- [ ] core/module/module_exec_spec.rb
- [ ] core/module/module_function_spec.rb
- [ ] core/module/name_spec.rb
- [ ] core/module/nesting_spec.rb
- [ ] core/module/new_spec.rb
- [ ] core/module/prepend_features_spec.rb
- [ ] core/module/prepend_spec.rb
- [ ] core/module/prepended_spec.rb
- [ ] core/module/private_class_method_spec.rb
- [ ] core/module/private_constant_spec.rb
- [ ] core/module/private_instance_methods_spec.rb
- [ ] core/module/private_method_defined_spec.rb
- [ ] core/module/private_spec.rb
- [ ] core/module/protected_instance_methods_spec.rb
- [ ] core/module/protected_method_defined_spec.rb
- [ ] core/module/protected_spec.rb
- [ ] core/module/public_class_method_spec.rb
- [ ] core/module/public_constant_spec.rb
- [ ] core/module/public_instance_method_spec.rb
- [ ] core/module/public_instance_methods_spec.rb
- [ ] core/module/public_method_defined_spec.rb
- [ ] core/module/public_spec.rb
- [ ] core/module/refine_spec.rb
- [ ] core/module/refinements_spec.rb
- [ ] core/module/remove_class_variable_spec.rb
- [ ] core/module/remove_const_spec.rb
- [ ] core/module/remove_method_spec.rb
- [ ] core/module/ruby2_keywords_spec.rb
- [ ] core/module/set_temporary_name_spec.rb
- [ ] core/module/singleton_class_spec.rb
- [-] core/module/to_s_spec.rb
- [ ] core/module/undef_method_spec.rb
- [ ] core/module/undefined_instance_methods_spec.rb
- [ ] core/module/used_refinements_spec.rb
- [ ] core/module/using_spec.rb

### core/mutex
- [ ] core/mutex/lock_spec.rb
- [ ] core/mutex/locked_spec.rb
- [ ] core/mutex/owned_spec.rb
- [ ] core/mutex/sleep_spec.rb
- [ ] core/mutex/synchronize_spec.rb
- [ ] core/mutex/try_lock_spec.rb
- [ ] core/mutex/unlock_spec.rb

### core/nil
- [ ] core/nil/and_spec.rb
- [ ] core/nil/case_compare_spec.rb
- [ ] core/nil/dup_spec.rb
- [ ] core/nil/inspect_spec.rb
- [ ] core/nil/match_spec.rb
- [ ] core/nil/nil_spec.rb
- [ ] core/nil/nilclass_spec.rb
- [ ] core/nil/or_spec.rb
- [ ] core/nil/rationalize_spec.rb
- [ ] core/nil/singleton_method_spec.rb
- [ ] core/nil/to_a_spec.rb
- [ ] core/nil/to_c_spec.rb
- [ ] core/nil/to_f_spec.rb
- [ ] core/nil/to_h_spec.rb
- [ ] core/nil/to_i_spec.rb
- [ ] core/nil/to_r_spec.rb
- [ ] core/nil/to_s_spec.rb
- [ ] core/nil/xor_spec.rb

### core/numeric
- [ ] core/numeric/abs2_spec.rb
- [ ] core/numeric/abs_spec.rb
- [ ] core/numeric/angle_spec.rb
- [ ] core/numeric/arg_spec.rb
- [ ] core/numeric/ceil_spec.rb
- [ ] core/numeric/clone_spec.rb
- [ ] core/numeric/coerce_spec.rb
- [ ] core/numeric/comparison_spec.rb
- [ ] core/numeric/conj_spec.rb
- [ ] core/numeric/conjugate_spec.rb
- [ ] core/numeric/denominator_spec.rb
- [ ] core/numeric/div_spec.rb
- [ ] core/numeric/divmod_spec.rb
- [ ] core/numeric/dup_spec.rb
- [ ] core/numeric/eql_spec.rb
- [ ] core/numeric/fdiv_spec.rb
- [ ] core/numeric/finite_spec.rb
- [ ] core/numeric/floor_spec.rb
- [ ] core/numeric/i_spec.rb
- [ ] core/numeric/imag_spec.rb
- [ ] core/numeric/imaginary_spec.rb
- [ ] core/numeric/infinite_spec.rb
- [ ] core/numeric/integer_spec.rb
- [ ] core/numeric/magnitude_spec.rb
- [ ] core/numeric/modulo_spec.rb
- [ ] core/numeric/negative_spec.rb
- [ ] core/numeric/nonzero_spec.rb
- [ ] core/numeric/numerator_spec.rb
- [ ] core/numeric/numeric_spec.rb
- [ ] core/numeric/phase_spec.rb
- [ ] core/numeric/polar_spec.rb
- [ ] core/numeric/positive_spec.rb
- [ ] core/numeric/quo_spec.rb
- [ ] core/numeric/real_spec.rb
- [ ] core/numeric/rect_spec.rb
- [ ] core/numeric/rectangular_spec.rb
- [ ] core/numeric/remainder_spec.rb
- [ ] core/numeric/round_spec.rb
- [ ] core/numeric/singleton_method_added_spec.rb
- [ ] core/numeric/step_spec.rb
- [ ] core/numeric/to_c_spec.rb
- [ ] core/numeric/to_int_spec.rb
- [ ] core/numeric/truncate_spec.rb
- [ ] core/numeric/uminus_spec.rb
- [ ] core/numeric/uplus_spec.rb
- [ ] core/numeric/zero_spec.rb

### core/objectspace
- [ ] core/objectspace/_id2ref_spec.rb
- [ ] core/objectspace/count_objects_spec.rb
- [ ] core/objectspace/define_finalizer_spec.rb
- [ ] core/objectspace/each_object_spec.rb
- [ ] core/objectspace/garbage_collect_spec.rb
- [ ] core/objectspace/undefine_finalizer_spec.rb

### core/objectspace/weakkeymap
- [ ] core/objectspace/weakkeymap/clear_spec.rb
- [ ] core/objectspace/weakkeymap/delete_spec.rb
- [ ] core/objectspace/weakkeymap/element_reference_spec.rb
- [ ] core/objectspace/weakkeymap/element_set_spec.rb
- [ ] core/objectspace/weakkeymap/getkey_spec.rb
- [ ] core/objectspace/weakkeymap/inspect_spec.rb
- [ ] core/objectspace/weakkeymap/key_spec.rb

### core/objectspace/weakmap
- [ ] core/objectspace/weakmap/delete_spec.rb
- [ ] core/objectspace/weakmap/each_key_spec.rb
- [ ] core/objectspace/weakmap/each_pair_spec.rb
- [ ] core/objectspace/weakmap/each_spec.rb
- [ ] core/objectspace/weakmap/each_value_spec.rb
- [ ] core/objectspace/weakmap/element_reference_spec.rb
- [ ] core/objectspace/weakmap/element_set_spec.rb
- [ ] core/objectspace/weakmap/include_spec.rb
- [ ] core/objectspace/weakmap/inspect_spec.rb
- [ ] core/objectspace/weakmap/key_spec.rb
- [ ] core/objectspace/weakmap/keys_spec.rb
- [ ] core/objectspace/weakmap/length_spec.rb
- [ ] core/objectspace/weakmap/member_spec.rb
- [ ] core/objectspace/weakmap/size_spec.rb
- [ ] core/objectspace/weakmap/values_spec.rb

### core/objectspace
- [ ] core/objectspace/weakmap_spec.rb

### core/proc
- [ ] core/proc/allocate_spec.rb
- [ ] core/proc/arity_spec.rb
- [ ] core/proc/binding_spec.rb
- [ ] core/proc/block_pass_spec.rb
- [ ] core/proc/call_spec.rb
- [ ] core/proc/case_compare_spec.rb
- [ ] core/proc/clone_spec.rb
- [ ] core/proc/compose_spec.rb
- [ ] core/proc/curry_spec.rb
- [ ] core/proc/dup_spec.rb
- [ ] core/proc/element_reference_spec.rb
- [ ] core/proc/eql_spec.rb
- [ ] core/proc/equal_value_spec.rb
- [ ] core/proc/hash_spec.rb
- [ ] core/proc/inspect_spec.rb
- [ ] core/proc/lambda_spec.rb
- [ ] core/proc/new_spec.rb
- [ ] core/proc/parameters_spec.rb
- [ ] core/proc/ruby2_keywords_spec.rb
- [ ] core/proc/source_location_spec.rb
- [ ] core/proc/to_proc_spec.rb
- [ ] core/proc/to_s_spec.rb
- [ ] core/proc/yield_spec.rb

### core/process
- [ ] core/process/_fork_spec.rb
- [ ] core/process/abort_spec.rb
- [ ] core/process/argv0_spec.rb
- [ ] core/process/clock_getres_spec.rb
- [ ] core/process/clock_gettime_spec.rb
- [ ] core/process/constants_spec.rb
- [ ] core/process/daemon_spec.rb
- [ ] core/process/detach_spec.rb
- [ ] core/process/egid_spec.rb
- [ ] core/process/euid_spec.rb
- [ ] core/process/exec_spec.rb
- [ ] core/process/exit_spec.rb
- [ ] core/process/fork_spec.rb
- [ ] core/process/getpgid_spec.rb
- [ ] core/process/getpgrp_spec.rb
- [ ] core/process/getpriority_spec.rb
- [ ] core/process/getrlimit_spec.rb

### core/process/gid
- [ ] core/process/gid/change_privilege_spec.rb
- [ ] core/process/gid/eid_spec.rb
- [ ] core/process/gid/grant_privilege_spec.rb
- [ ] core/process/gid/re_exchange_spec.rb
- [ ] core/process/gid/re_exchangeable_spec.rb
- [ ] core/process/gid/rid_spec.rb
- [ ] core/process/gid/sid_available_spec.rb
- [ ] core/process/gid/switch_spec.rb

### core/process
- [ ] core/process/gid_spec.rb
- [ ] core/process/groups_spec.rb
- [ ] core/process/initgroups_spec.rb
- [ ] core/process/kill_spec.rb
- [ ] core/process/last_status_spec.rb
- [ ] core/process/maxgroups_spec.rb
- [ ] core/process/pid_spec.rb
- [ ] core/process/ppid_spec.rb
- [ ] core/process/set_proctitle_spec.rb
- [ ] core/process/setpgid_spec.rb
- [ ] core/process/setpgrp_spec.rb
- [ ] core/process/setpriority_spec.rb
- [ ] core/process/setrlimit_spec.rb
- [ ] core/process/setsid_spec.rb
- [ ] core/process/spawn_spec.rb

### core/process/status
- [ ] core/process/status/bit_and_spec.rb
- [ ] core/process/status/coredump_spec.rb
- [ ] core/process/status/equal_value_spec.rb
- [ ] core/process/status/exited_spec.rb
- [ ] core/process/status/exitstatus_spec.rb
- [ ] core/process/status/inspect_spec.rb
- [ ] core/process/status/pid_spec.rb
- [ ] core/process/status/right_shift_spec.rb
- [ ] core/process/status/signaled_spec.rb
- [ ] core/process/status/stopped_spec.rb
- [ ] core/process/status/stopsig_spec.rb
- [ ] core/process/status/success_spec.rb
- [ ] core/process/status/termsig_spec.rb
- [ ] core/process/status/to_i_spec.rb
- [ ] core/process/status/to_int_spec.rb
- [ ] core/process/status/to_s_spec.rb
- [ ] core/process/status/wait_spec.rb

### core/process/sys
- [ ] core/process/sys/getegid_spec.rb
- [ ] core/process/sys/geteuid_spec.rb
- [ ] core/process/sys/getgid_spec.rb
- [ ] core/process/sys/getuid_spec.rb
- [ ] core/process/sys/issetugid_spec.rb
- [ ] core/process/sys/setegid_spec.rb
- [ ] core/process/sys/seteuid_spec.rb
- [ ] core/process/sys/setgid_spec.rb
- [ ] core/process/sys/setregid_spec.rb
- [ ] core/process/sys/setresgid_spec.rb
- [ ] core/process/sys/setresuid_spec.rb
- [ ] core/process/sys/setreuid_spec.rb
- [ ] core/process/sys/setrgid_spec.rb
- [ ] core/process/sys/setruid_spec.rb
- [ ] core/process/sys/setuid_spec.rb

### core/process
- [ ] core/process/times_spec.rb

### core/process/tms
- [ ] core/process/tms/cstime_spec.rb
- [ ] core/process/tms/cutime_spec.rb
- [ ] core/process/tms/stime_spec.rb
- [ ] core/process/tms/utime_spec.rb

### core/process/uid
- [ ] core/process/uid/change_privilege_spec.rb
- [ ] core/process/uid/eid_spec.rb
- [ ] core/process/uid/grant_privilege_spec.rb
- [ ] core/process/uid/re_exchange_spec.rb
- [ ] core/process/uid/re_exchangeable_spec.rb
- [ ] core/process/uid/rid_spec.rb
- [ ] core/process/uid/sid_available_spec.rb
- [ ] core/process/uid/switch_spec.rb

### core/process
- [ ] core/process/uid_spec.rb
- [ ] core/process/wait2_spec.rb
- [ ] core/process/wait_spec.rb
- [ ] core/process/waitall_spec.rb
- [ ] core/process/waitpid2_spec.rb
- [ ] core/process/waitpid_spec.rb
- [ ] core/process/warmup_spec.rb

### core/queue
- [ ] core/queue/append_spec.rb
- [ ] core/queue/clear_spec.rb
- [ ] core/queue/close_spec.rb
- [ ] core/queue/closed_spec.rb
- [ ] core/queue/deq_spec.rb
- [ ] core/queue/empty_spec.rb
- [ ] core/queue/enq_spec.rb
- [ ] core/queue/freeze_spec.rb
- [ ] core/queue/initialize_spec.rb
- [ ] core/queue/length_spec.rb
- [ ] core/queue/num_waiting_spec.rb
- [ ] core/queue/pop_spec.rb
- [ ] core/queue/push_spec.rb
- [ ] core/queue/shift_spec.rb
- [ ] core/queue/size_spec.rb

### core/random
- [ ] core/random/bytes_spec.rb
- [ ] core/random/default_spec.rb
- [ ] core/random/equal_value_spec.rb
- [ ] core/random/new_seed_spec.rb
- [ ] core/random/new_spec.rb
- [ ] core/random/rand_spec.rb
- [ ] core/random/random_number_spec.rb
- [ ] core/random/seed_spec.rb
- [ ] core/random/srand_spec.rb
- [ ] core/random/urandom_spec.rb

### core/range
- [ ] core/range/begin_spec.rb
- [ ] core/range/bsearch_spec.rb
- [ ] core/range/case_compare_spec.rb
- [ ] core/range/clone_spec.rb
- [ ] core/range/count_spec.rb
- [ ] core/range/cover_spec.rb
- [ ] core/range/dup_spec.rb
- [ ] core/range/each_spec.rb
- [ ] core/range/end_spec.rb
- [ ] core/range/eql_spec.rb
- [ ] core/range/equal_value_spec.rb
- [ ] core/range/exclude_end_spec.rb
- [ ] core/range/first_spec.rb
- [ ] core/range/frozen_spec.rb
- [ ] core/range/hash_spec.rb
- [ ] core/range/include_spec.rb
- [ ] core/range/initialize_spec.rb
- [x] core/range/inspect_spec.rb
- [ ] core/range/last_spec.rb
- [ ] core/range/max_spec.rb
- [ ] core/range/member_spec.rb
- [ ] core/range/min_spec.rb
- [ ] core/range/minmax_spec.rb
- [ ] core/range/new_spec.rb
- [ ] core/range/overlap_spec.rb
- [ ] core/range/percent_spec.rb
- [ ] core/range/range_spec.rb
- [ ] core/range/reverse_each_spec.rb
- [ ] core/range/size_spec.rb
- [ ] core/range/step_spec.rb
- [ ] core/range/to_a_spec.rb
- [ ] core/range/to_s_spec.rb
- [ ] core/range/to_set_spec.rb

### core/rational
- [ ] core/rational/abs_spec.rb
- [ ] core/rational/ceil_spec.rb
- [ ] core/rational/comparison_spec.rb
- [ ] core/rational/denominator_spec.rb
- [ ] core/rational/div_spec.rb
- [ ] core/rational/divide_spec.rb
- [ ] core/rational/divmod_spec.rb
- [ ] core/rational/equal_value_spec.rb
- [ ] core/rational/exponent_spec.rb
- [ ] core/rational/fdiv_spec.rb
- [ ] core/rational/floor_spec.rb
- [ ] core/rational/hash_spec.rb
- [ ] core/rational/inspect_spec.rb
- [ ] core/rational/integer_spec.rb
- [ ] core/rational/magnitude_spec.rb
- [ ] core/rational/marshal_dump_spec.rb
- [ ] core/rational/minus_spec.rb
- [ ] core/rational/modulo_spec.rb
- [ ] core/rational/multiply_spec.rb
- [ ] core/rational/numerator_spec.rb
- [ ] core/rational/plus_spec.rb
- [ ] core/rational/quo_spec.rb
- [ ] core/rational/rational_spec.rb
- [ ] core/rational/rationalize_spec.rb
- [ ] core/rational/remainder_spec.rb
- [ ] core/rational/round_spec.rb
- [ ] core/rational/to_f_spec.rb
- [ ] core/rational/to_i_spec.rb
- [ ] core/rational/to_r_spec.rb
- [ ] core/rational/to_s_spec.rb
- [ ] core/rational/truncate_spec.rb
- [ ] core/rational/zero_spec.rb

### core/refinement
- [ ] core/refinement/append_features_spec.rb
- [ ] core/refinement/extend_object_spec.rb
- [ ] core/refinement/import_methods_spec.rb
- [ ] core/refinement/include_spec.rb
- [ ] core/refinement/prepend_features_spec.rb
- [ ] core/refinement/prepend_spec.rb
- [ ] core/refinement/refined_class_spec.rb
- [ ] core/refinement/target_spec.rb

### core/regexp
- [ ] core/regexp/case_compare_spec.rb
- [ ] core/regexp/casefold_spec.rb
- [ ] core/regexp/compile_spec.rb
- [ ] core/regexp/encoding_spec.rb
- [ ] core/regexp/eql_spec.rb
- [ ] core/regexp/equal_value_spec.rb
- [ ] core/regexp/escape_spec.rb
- [ ] core/regexp/fixed_encoding_spec.rb
- [ ] core/regexp/hash_spec.rb
- [ ] core/regexp/initialize_spec.rb
- [ ] core/regexp/inspect_spec.rb
- [ ] core/regexp/last_match_spec.rb
- [ ] core/regexp/linear_time_spec.rb
- [ ] core/regexp/match_spec.rb
- [ ] core/regexp/named_captures_spec.rb
- [ ] core/regexp/names_spec.rb
- [ ] core/regexp/new_spec.rb
- [ ] core/regexp/options_spec.rb
- [ ] core/regexp/quote_spec.rb
- [ ] core/regexp/source_spec.rb
- [ ] core/regexp/timeout_spec.rb
- [ ] core/regexp/to_s_spec.rb
- [ ] core/regexp/try_convert_spec.rb
- [ ] core/regexp/union_spec.rb

### core/set
- [ ] core/set/add_spec.rb
- [ ] core/set/append_spec.rb
- [ ] core/set/case_compare_spec.rb
- [ ] core/set/case_equality_spec.rb
- [ ] core/set/classify_spec.rb
- [ ] core/set/clear_spec.rb
- [ ] core/set/collect_spec.rb
- [ ] core/set/compare_by_identity_spec.rb
- [ ] core/set/comparison_spec.rb
- [ ] core/set/constructor_spec.rb
- [ ] core/set/delete_if_spec.rb
- [ ] core/set/delete_spec.rb
- [ ] core/set/difference_spec.rb
- [ ] core/set/disjoint_spec.rb
- [ ] core/set/divide_spec.rb
- [ ] core/set/each_spec.rb
- [ ] core/set/empty_spec.rb

### core/set/enumerable
- [ ] core/set/enumerable/to_set_spec.rb

### core/set
- [ ] core/set/eql_spec.rb
- [ ] core/set/equal_value_spec.rb
- [ ] core/set/exclusion_spec.rb
- [ ] core/set/filter_spec.rb
- [ ] core/set/flatten_merge_spec.rb
- [ ] core/set/flatten_spec.rb
- [ ] core/set/hash_spec.rb
- [ ] core/set/include_spec.rb
- [ ] core/set/initialize_clone_spec.rb
- [ ] core/set/initialize_spec.rb
- [ ] core/set/inspect_spec.rb
- [ ] core/set/intersect_spec.rb
- [ ] core/set/intersection_spec.rb
- [ ] core/set/join_spec.rb
- [ ] core/set/keep_if_spec.rb
- [ ] core/set/length_spec.rb
- [ ] core/set/map_spec.rb
- [ ] core/set/member_spec.rb
- [ ] core/set/merge_spec.rb
- [ ] core/set/minus_spec.rb
- [ ] core/set/plus_spec.rb
- [ ] core/set/pretty_print_cycle_spec.rb
- [ ] core/set/proper_subset_spec.rb
- [ ] core/set/proper_superset_spec.rb
- [ ] core/set/reject_spec.rb
- [ ] core/set/replace_spec.rb
- [ ] core/set/select_spec.rb
- [ ] core/set/set_spec.rb
- [ ] core/set/size_spec.rb

### core/set/sortedset
- [ ] core/set/sortedset/sortedset_spec.rb

### core/set
- [ ] core/set/subset_spec.rb
- [ ] core/set/subtract_spec.rb
- [ ] core/set/superset_spec.rb
- [ ] core/set/to_a_spec.rb
- [ ] core/set/to_s_spec.rb
- [ ] core/set/union_spec.rb

### core/signal
- [ ] core/signal/list_spec.rb
- [ ] core/signal/signame_spec.rb
- [ ] core/signal/trap_spec.rb

### core/sizedqueue
- [ ] core/sizedqueue/append_spec.rb
- [ ] core/sizedqueue/clear_spec.rb
- [ ] core/sizedqueue/close_spec.rb
- [ ] core/sizedqueue/closed_spec.rb
- [ ] core/sizedqueue/deq_spec.rb
- [ ] core/sizedqueue/empty_spec.rb
- [ ] core/sizedqueue/enq_spec.rb
- [ ] core/sizedqueue/freeze_spec.rb
- [ ] core/sizedqueue/length_spec.rb
- [ ] core/sizedqueue/max_spec.rb
- [ ] core/sizedqueue/new_spec.rb
- [ ] core/sizedqueue/num_waiting_spec.rb
- [ ] core/sizedqueue/pop_spec.rb
- [ ] core/sizedqueue/push_spec.rb
- [ ] core/sizedqueue/shift_spec.rb
- [ ] core/sizedqueue/size_spec.rb

### core/string
- [x] core/string/allocate_spec.rb
- [x] core/string/append_as_bytes_spec.rb
- [x] core/string/append_spec.rb
- [x] core/string/ascii_only_spec.rb
- [x] core/string/b_spec.rb
- [ ] core/string/byteindex_spec.rb
- [ ] core/string/byterindex_spec.rb
- [x] core/string/bytes_spec.rb
- [x] core/string/bytesize_spec.rb
- [x] core/string/byteslice_spec.rb
- [ ] core/string/bytesplice_spec.rb
- [x] core/string/capitalize_spec.rb
- [x] core/string/case_compare_spec.rb
- [x] core/string/casecmp_spec.rb
- [ ] core/string/center_spec.rb
- [x] core/string/chars_spec.rb
- [ ] core/string/chilled_string_spec.rb
- [ ] core/string/chomp_spec.rb
- [x] core/string/chop_spec.rb
- [x] core/string/chr_spec.rb
- [x] core/string/clear_spec.rb
- [x] core/string/clone_spec.rb
- [x] core/string/codepoints_spec.rb
- [x] core/string/comparison_spec.rb
- [x] core/string/concat_spec.rb
- [ ] core/string/count_spec.rb
- [ ] core/string/crypt_spec.rb
- [x] core/string/dedup_spec.rb
- [x] core/string/delete_prefix_spec.rb
- [x] core/string/delete_spec.rb
- [x] core/string/delete_suffix_spec.rb
- [x] core/string/downcase_spec.rb
- [ ] core/string/dump_spec.rb
- [x] core/string/dup_spec.rb
- [x] core/string/each_byte_spec.rb
- [x] core/string/each_char_spec.rb
- [x] core/string/each_codepoint_spec.rb
- [ ] core/string/each_grapheme_cluster_spec.rb
- [ ] core/string/each_line_spec.rb
- [x] core/string/element_reference_spec.rb
- [x] core/string/element_set_spec.rb
- [x] core/string/empty_spec.rb
- [x] core/string/encode_spec.rb
- [x] core/string/encoding_spec.rb
- [x] core/string/end_with_spec.rb
- [x] core/string/eql_spec.rb
- [x] core/string/equal_value_spec.rb
- [x] core/string/force_encoding_spec.rb
- [x] core/string/freeze_spec.rb
- [x] core/string/getbyte_spec.rb
- [ ] core/string/grapheme_clusters_spec.rb
- [ ] core/string/gsub_spec.rb
- [x] core/string/hash_spec.rb
- [x] core/string/hex_spec.rb
- [x] core/string/include_spec.rb
- [x] core/string/index_spec.rb
- [x] core/string/initialize_spec.rb
- [x] core/string/insert_spec.rb
- [x] core/string/inspect_spec.rb
- [x] core/string/intern_spec.rb
- [x] core/string/length_spec.rb
- [ ] core/string/lines_spec.rb
- [ ] core/string/ljust_spec.rb
- [ ] core/string/lstrip_spec.rb
- [x] core/string/match_spec.rb
- [ ] core/string/modulo_spec.rb
- [x] core/string/multiply_spec.rb
- [x] core/string/new_spec.rb
- [x] core/string/next_spec.rb
- [x] core/string/oct_spec.rb
- [x] core/string/ord_spec.rb
- [ ] core/string/partition_spec.rb
- [x] core/string/plus_spec.rb
- [x] core/string/prepend_spec.rb
- [x] core/string/replace_spec.rb
- [x] core/string/reverse_spec.rb
- [ ] core/string/rindex_spec.rb
- [ ] core/string/rjust_spec.rb
- [ ] core/string/rpartition_spec.rb
- [ ] core/string/rstrip_spec.rb
- [x] core/string/scan_spec.rb
- [ ] core/string/scrub_spec.rb
- [x] core/string/setbyte_spec.rb
- [x] core/string/size_spec.rb
- [x] core/string/slice_spec.rb
- [x] core/string/split_spec.rb
- [ ] core/string/squeeze_spec.rb
- [x] core/string/start_with_spec.rb
- [x] core/string/string_spec.rb
- [ ] core/string/strip_spec.rb
- [ ] core/string/sub_spec.rb
- [x] core/string/succ_spec.rb
- [ ] core/string/sum_spec.rb
- [ ] core/string/swapcase_spec.rb
- [ ] core/string/to_c_spec.rb
- [x] core/string/to_f_spec.rb
- [x] core/string/to_i_spec.rb
- [ ] core/string/to_r_spec.rb
- [x] core/string/to_s_spec.rb
- [x] core/string/to_str_spec.rb
- [x] core/string/to_sym_spec.rb
- [ ] core/string/tr_s_spec.rb
- [ ] core/string/tr_spec.rb
- [x] core/string/try_convert_spec.rb
- [x] core/string/uminus_spec.rb
- [ ] core/string/undump_spec.rb
- [ ] core/string/unicode_normalize_spec.rb
- [ ] core/string/unicode_normalized_spec.rb

### core/string/unpack
- [x] core/string/unpack/a_spec.rb
- [x] core/string/unpack/at_spec.rb
- [x] core/string/unpack/b_spec.rb
- [x] core/string/unpack/c_spec.rb
- [x] core/string/unpack/comment_spec.rb
- [x] core/string/unpack/d_spec.rb
- [x] core/string/unpack/e_spec.rb
- [x] core/string/unpack/f_spec.rb
- [x] core/string/unpack/g_spec.rb
- [x] core/string/unpack/h_spec.rb
- [x] core/string/unpack/i_spec.rb
- [x] core/string/unpack/j_spec.rb
- [x] core/string/unpack/l_spec.rb
- [x] core/string/unpack/m_spec.rb
- [x] core/string/unpack/n_spec.rb
- [x] core/string/unpack/p_spec.rb
- [x] core/string/unpack/percent_spec.rb
- [x] core/string/unpack/q_spec.rb
- [x] core/string/unpack/s_spec.rb
- [x] core/string/unpack/u_spec.rb
- [x] core/string/unpack/v_spec.rb
- [x] core/string/unpack/w_spec.rb
- [x] core/string/unpack/x_spec.rb
- [x] core/string/unpack/z_spec.rb

### core/string
- [x] core/string/unpack1_spec.rb
- [x] core/string/unpack_spec.rb
- [x] core/string/upcase_spec.rb
- [x] core/string/uplus_spec.rb
- [ ] core/string/upto_spec.rb

### core/string/valid_encoding
- [x] core/string/valid_encoding/utf_8_spec.rb

### core/string
- [x] core/string/valid_encoding_spec.rb

### core/struct
- [ ] core/struct/clone_spec.rb
- [ ] core/struct/constants_spec.rb
- [ ] core/struct/deconstruct_keys_spec.rb
- [ ] core/struct/deconstruct_spec.rb
- [ ] core/struct/dig_spec.rb
- [ ] core/struct/dup_spec.rb
- [ ] core/struct/each_pair_spec.rb
- [ ] core/struct/each_spec.rb
- [ ] core/struct/element_reference_spec.rb
- [ ] core/struct/element_set_spec.rb
- [ ] core/struct/eql_spec.rb
- [ ] core/struct/equal_value_spec.rb
- [ ] core/struct/filter_spec.rb
- [ ] core/struct/hash_spec.rb
- [ ] core/struct/initialize_spec.rb
- [ ] core/struct/inspect_spec.rb
- [ ] core/struct/instance_variable_get_spec.rb
- [ ] core/struct/instance_variables_spec.rb
- [ ] core/struct/keyword_init_spec.rb
- [ ] core/struct/length_spec.rb
- [ ] core/struct/members_spec.rb
- [ ] core/struct/new_spec.rb
- [ ] core/struct/select_spec.rb
- [ ] core/struct/size_spec.rb
- [ ] core/struct/struct_spec.rb
- [ ] core/struct/to_a_spec.rb
- [ ] core/struct/to_h_spec.rb
- [ ] core/struct/to_s_spec.rb
- [ ] core/struct/values_at_spec.rb
- [ ] core/struct/values_spec.rb

### core/symbol
- [ ] core/symbol/all_symbols_spec.rb
- [ ] core/symbol/capitalize_spec.rb
- [ ] core/symbol/case_compare_spec.rb
- [ ] core/symbol/casecmp_spec.rb
- [ ] core/symbol/comparison_spec.rb
- [x] core/symbol/downcase_spec.rb
- [ ] core/symbol/dup_spec.rb
- [ ] core/symbol/element_reference_spec.rb
- [x] core/symbol/empty_spec.rb
- [x] core/symbol/encoding_spec.rb
- [x] core/symbol/end_with_spec.rb
- [x] core/symbol/equal_value_spec.rb
- [x] core/symbol/id2name_spec.rb
- [x] core/symbol/inspect_spec.rb
- [x] core/symbol/intern_spec.rb
- [x] core/symbol/length_spec.rb
- [ ] core/symbol/match_spec.rb
- [x] core/symbol/name_spec.rb
- [ ] core/symbol/next_spec.rb
- [x] core/symbol/size_spec.rb
- [ ] core/symbol/slice_spec.rb
- [x] core/symbol/start_with_spec.rb
- [ ] core/symbol/succ_spec.rb
- [ ] core/symbol/swapcase_spec.rb
- [x] core/symbol/symbol_spec.rb
- [ ] core/symbol/to_proc_spec.rb
- [x] core/symbol/to_s_spec.rb
- [x] core/symbol/to_sym_spec.rb
- [x] core/symbol/upcase_spec.rb

### core/systemexit
- [ ] core/systemexit/initialize_spec.rb
- [ ] core/systemexit/success_spec.rb

### core/thread
- [ ] core/thread/abort_on_exception_spec.rb
- [ ] core/thread/add_trace_func_spec.rb
- [x] core/thread/alive_spec.rb
- [ ] core/thread/allocate_spec.rb

### core/thread/backtrace
- [ ] core/thread/backtrace/limit_spec.rb

### core/thread/backtrace/location
- [ ] core/thread/backtrace/location/absolute_path_spec.rb
- [ ] core/thread/backtrace/location/base_label_spec.rb
- [ ] core/thread/backtrace/location/inspect_spec.rb
- [ ] core/thread/backtrace/location/label_spec.rb
- [ ] core/thread/backtrace/location/lineno_spec.rb
- [ ] core/thread/backtrace/location/path_spec.rb
- [ ] core/thread/backtrace/location/to_s_spec.rb

### core/thread
- [ ] core/thread/backtrace_locations_spec.rb
- [ ] core/thread/backtrace_spec.rb
- [x] core/thread/current_spec.rb
- [ ] core/thread/each_caller_location_spec.rb
- [-] core/thread/element_reference_spec.rb
- [-] core/thread/element_set_spec.rb
- [ ] core/thread/exit_spec.rb
- [ ] core/thread/fetch_spec.rb
- [ ] core/thread/fork_spec.rb
- [ ] core/thread/group_spec.rb
- [ ] core/thread/handle_interrupt_spec.rb
- [ ] core/thread/ignore_deadlock_spec.rb
- [ ] core/thread/initialize_spec.rb
- [ ] core/thread/inspect_spec.rb
- [x] core/thread/join_spec.rb
- [ ] core/thread/key_spec.rb
- [ ] core/thread/keys_spec.rb
- [ ] core/thread/kill_spec.rb
- [-] core/thread/list_spec.rb
- [x] core/thread/main_spec.rb
- [-] core/thread/name_spec.rb
- [ ] core/thread/native_thread_id_spec.rb
- [x] core/thread/new_spec.rb
- [x] core/thread/pass_spec.rb
- [ ] core/thread/pending_interrupt_spec.rb
- [ ] core/thread/priority_spec.rb
- [ ] core/thread/raise_spec.rb
- [ ] core/thread/report_on_exception_spec.rb
- [ ] core/thread/run_spec.rb
- [ ] core/thread/set_trace_func_spec.rb
- [ ] core/thread/start_spec.rb
- [x] core/thread/status_spec.rb
- [x] core/thread/stop_spec.rb
- [ ] core/thread/terminate_spec.rb
- [-] core/thread/thread_variable_get_spec.rb
- [-] core/thread/thread_variable_set_spec.rb
- [-] core/thread/thread_variable_spec.rb
- [-] core/thread/thread_variables_spec.rb
- [ ] core/thread/to_s_spec.rb
- [-] core/thread/value_spec.rb
- [ ] core/thread/wakeup_spec.rb

### core/threadgroup
- [ ] core/threadgroup/add_spec.rb
- [ ] core/threadgroup/default_spec.rb
- [ ] core/threadgroup/enclose_spec.rb
- [ ] core/threadgroup/enclosed_spec.rb
- [ ] core/threadgroup/list_spec.rb

### core/time
- [ ] core/time/_dump_spec.rb
- [ ] core/time/_load_spec.rb
- [ ] core/time/asctime_spec.rb
- [ ] core/time/at_spec.rb
- [ ] core/time/ceil_spec.rb
- [ ] core/time/comparison_spec.rb
- [ ] core/time/ctime_spec.rb
- [ ] core/time/day_spec.rb
- [ ] core/time/deconstruct_keys_spec.rb
- [ ] core/time/dst_spec.rb
- [ ] core/time/dup_spec.rb
- [ ] core/time/eql_spec.rb
- [ ] core/time/floor_spec.rb
- [ ] core/time/friday_spec.rb
- [ ] core/time/getgm_spec.rb
- [ ] core/time/getlocal_spec.rb
- [ ] core/time/getutc_spec.rb
- [ ] core/time/gm_spec.rb
- [ ] core/time/gmt_offset_spec.rb
- [ ] core/time/gmt_spec.rb
- [ ] core/time/gmtime_spec.rb
- [ ] core/time/gmtoff_spec.rb
- [ ] core/time/hash_spec.rb
- [ ] core/time/hour_spec.rb
- [ ] core/time/inspect_spec.rb
- [ ] core/time/isdst_spec.rb
- [ ] core/time/iso8601_spec.rb
- [ ] core/time/local_spec.rb
- [ ] core/time/localtime_spec.rb
- [ ] core/time/mday_spec.rb
- [ ] core/time/min_spec.rb
- [ ] core/time/minus_spec.rb
- [ ] core/time/mktime_spec.rb
- [ ] core/time/mon_spec.rb
- [ ] core/time/monday_spec.rb
- [ ] core/time/month_spec.rb
- [ ] core/time/new_spec.rb
- [ ] core/time/now_spec.rb
- [ ] core/time/nsec_spec.rb
- [ ] core/time/plus_spec.rb
- [ ] core/time/round_spec.rb
- [ ] core/time/saturday_spec.rb
- [ ] core/time/sec_spec.rb
- [ ] core/time/strftime_spec.rb
- [ ] core/time/subsec_spec.rb
- [ ] core/time/sunday_spec.rb
- [ ] core/time/thursday_spec.rb
- [ ] core/time/time_spec.rb
- [ ] core/time/to_a_spec.rb
- [ ] core/time/to_f_spec.rb
- [ ] core/time/to_i_spec.rb
- [ ] core/time/to_r_spec.rb
- [ ] core/time/to_s_spec.rb
- [ ] core/time/tuesday_spec.rb
- [ ] core/time/tv_nsec_spec.rb
- [ ] core/time/tv_sec_spec.rb
- [ ] core/time/tv_usec_spec.rb
- [ ] core/time/usec_spec.rb
- [ ] core/time/utc_offset_spec.rb
- [ ] core/time/utc_spec.rb
- [ ] core/time/wday_spec.rb
- [ ] core/time/wednesday_spec.rb
- [ ] core/time/xmlschema_spec.rb
- [ ] core/time/yday_spec.rb
- [ ] core/time/year_spec.rb
- [ ] core/time/zone_spec.rb

### core/tracepoint
- [ ] core/tracepoint/allow_reentry_spec.rb
- [ ] core/tracepoint/binding_spec.rb
- [ ] core/tracepoint/callee_id_spec.rb
- [ ] core/tracepoint/defined_class_spec.rb
- [ ] core/tracepoint/disable_spec.rb
- [ ] core/tracepoint/enable_spec.rb
- [ ] core/tracepoint/enabled_spec.rb
- [ ] core/tracepoint/eval_script_spec.rb
- [ ] core/tracepoint/event_spec.rb
- [ ] core/tracepoint/inspect_spec.rb
- [ ] core/tracepoint/lineno_spec.rb
- [ ] core/tracepoint/method_id_spec.rb
- [ ] core/tracepoint/new_spec.rb
- [ ] core/tracepoint/parameters_spec.rb
- [ ] core/tracepoint/path_spec.rb
- [ ] core/tracepoint/raised_exception_spec.rb
- [ ] core/tracepoint/return_value_spec.rb
- [ ] core/tracepoint/self_spec.rb
- [ ] core/tracepoint/trace_spec.rb

### core/true
- [ ] core/true/and_spec.rb
- [ ] core/true/case_compare_spec.rb
- [x] core/true/dup_spec.rb
- [x] core/true/inspect_spec.rb
- [ ] core/true/or_spec.rb
- [ ] core/true/singleton_method_spec.rb
- [x] core/true/to_s_spec.rb
- [ ] core/true/trueclass_spec.rb
- [ ] core/true/xor_spec.rb

### core/unboundmethod
- [ ] core/unboundmethod/arity_spec.rb
- [ ] core/unboundmethod/bind_call_spec.rb
- [ ] core/unboundmethod/bind_spec.rb
- [ ] core/unboundmethod/clone_spec.rb
- [ ] core/unboundmethod/dup_spec.rb
- [ ] core/unboundmethod/eql_spec.rb
- [ ] core/unboundmethod/equal_value_spec.rb
- [ ] core/unboundmethod/hash_spec.rb
- [ ] core/unboundmethod/inspect_spec.rb
- [ ] core/unboundmethod/name_spec.rb
- [ ] core/unboundmethod/original_name_spec.rb
- [ ] core/unboundmethod/owner_spec.rb
- [ ] core/unboundmethod/parameters_spec.rb
- [ ] core/unboundmethod/private_spec.rb
- [ ] core/unboundmethod/protected_spec.rb
- [ ] core/unboundmethod/public_spec.rb
- [ ] core/unboundmethod/source_location_spec.rb
- [ ] core/unboundmethod/super_method_spec.rb
- [ ] core/unboundmethod/to_s_spec.rb

### core/warning
- [ ] core/warning/categories_spec.rb
- [ ] core/warning/element_reference_spec.rb
- [ ] core/warning/element_set_spec.rb
- [ ] core/warning/performance_warning_spec.rb
- [ ] core/warning/warn_spec.rb

### language
- [ ] language/BEGIN_spec.rb
- [ ] language/END_spec.rb
- [ ] language/alias_spec.rb
- [ ] language/and_spec.rb
- [ ] language/array_spec.rb
- [ ] language/assignments_spec.rb
- [ ] language/block_spec.rb
- [ ] language/break_spec.rb
- [ ] language/case_spec.rb
- [ ] language/class_spec.rb
- [ ] language/class_variable_spec.rb
- [ ] language/comment_spec.rb
- [ ] language/constants_spec.rb
- [ ] language/def_spec.rb
- [ ] language/defined_spec.rb
- [ ] language/delegation_spec.rb
- [ ] language/encoding_spec.rb
- [ ] language/ensure_spec.rb
- [ ] language/execution_spec.rb
- [ ] language/file_spec.rb
- [ ] language/for_spec.rb
- [ ] language/hash_spec.rb
- [ ] language/heredoc_spec.rb
- [ ] language/if_spec.rb
- [ ] language/it_parameter_spec.rb
- [ ] language/keyword_arguments_spec.rb
- [ ] language/lambda_spec.rb
- [ ] language/line_spec.rb
- [ ] language/loop_spec.rb
- [ ] language/magic_comment_spec.rb
- [ ] language/match_spec.rb
- [ ] language/metaclass_spec.rb
- [ ] language/method_spec.rb
- [ ] language/module_spec.rb
- [ ] language/next_spec.rb
- [ ] language/not_spec.rb
- [ ] language/numbered_parameters_spec.rb
- [ ] language/numbers_spec.rb
- [ ] language/optional_assignments_spec.rb
- [ ] language/or_spec.rb
- [ ] language/order_spec.rb
- [ ] language/pattern_matching_spec.rb
- [ ] language/precedence_spec.rb

### language/predefined
- [ ] language/predefined/data_spec.rb
- [ ] language/predefined/toplevel_binding_spec.rb

### language
- [ ] language/predefined_spec.rb
- [ ] language/private_spec.rb
- [ ] language/proc_spec.rb
- [ ] language/range_spec.rb
- [ ] language/redo_spec.rb

### language/regexp
- [ ] language/regexp/anchors_spec.rb
- [ ] language/regexp/back-references_spec.rb
- [ ] language/regexp/character_classes_spec.rb
- [ ] language/regexp/empty_checks_spec.rb
- [ ] language/regexp/encoding_spec.rb
- [ ] language/regexp/escapes_spec.rb
- [ ] language/regexp/grouping_spec.rb
- [ ] language/regexp/interpolation_spec.rb
- [ ] language/regexp/modifiers_spec.rb
- [ ] language/regexp/repetition_spec.rb
- [ ] language/regexp/subexpression_call_spec.rb

### language
- [ ] language/regexp_spec.rb
- [ ] language/rescue_spec.rb
- [ ] language/retry_spec.rb
- [ ] language/return_spec.rb
- [ ] language/safe_navigator_spec.rb
- [ ] language/safe_spec.rb
- [ ] language/send_spec.rb
- [ ] language/singleton_class_spec.rb
- [ ] language/source_encoding_spec.rb
- [ ] language/string_spec.rb
- [ ] language/super_spec.rb
- [ ] language/symbol_spec.rb
- [ ] language/throw_spec.rb
- [ ] language/undef_spec.rb
- [ ] language/unless_spec.rb
- [ ] language/until_spec.rb
- [ ] language/variables_spec.rb
- [ ] language/while_spec.rb
- [ ] language/yield_spec.rb

### library/English
- [ ] library/English/English_spec.rb
- [ ] library/English/alias_spec.rb

### library/abbrev
- [ ] library/abbrev/abbrev_spec.rb

### library/base64
- [ ] library/base64/decode64_spec.rb
- [ ] library/base64/encode64_spec.rb
- [ ] library/base64/strict_decode64_spec.rb
- [ ] library/base64/strict_encode64_spec.rb
- [ ] library/base64/urlsafe_decode64_spec.rb
- [ ] library/base64/urlsafe_encode64_spec.rb

### library/bigdecimal
- [ ] library/bigdecimal/BigDecimal_spec.rb
- [ ] library/bigdecimal/abs_spec.rb
- [ ] library/bigdecimal/add_spec.rb
- [ ] library/bigdecimal/case_compare_spec.rb
- [ ] library/bigdecimal/ceil_spec.rb
- [ ] library/bigdecimal/clone_spec.rb
- [ ] library/bigdecimal/coerce_spec.rb
- [ ] library/bigdecimal/comparison_spec.rb
- [ ] library/bigdecimal/constants_spec.rb
- [ ] library/bigdecimal/core_spec.rb
- [ ] library/bigdecimal/div_spec.rb
- [ ] library/bigdecimal/divide_spec.rb
- [ ] library/bigdecimal/divmod_spec.rb
- [ ] library/bigdecimal/double_fig_spec.rb
- [ ] library/bigdecimal/dup_spec.rb
- [ ] library/bigdecimal/eql_spec.rb
- [ ] library/bigdecimal/equal_value_spec.rb
- [ ] library/bigdecimal/exponent_spec.rb
- [ ] library/bigdecimal/finite_spec.rb
- [ ] library/bigdecimal/fix_spec.rb
- [ ] library/bigdecimal/floor_spec.rb
- [ ] library/bigdecimal/frac_spec.rb
- [ ] library/bigdecimal/gt_spec.rb
- [ ] library/bigdecimal/gte_spec.rb
- [ ] library/bigdecimal/hash_spec.rb
- [ ] library/bigdecimal/infinite_spec.rb
- [ ] library/bigdecimal/inspect_spec.rb
- [ ] library/bigdecimal/limit_spec.rb
- [ ] library/bigdecimal/lt_spec.rb
- [ ] library/bigdecimal/lte_spec.rb
- [ ] library/bigdecimal/minus_spec.rb
- [ ] library/bigdecimal/mode_spec.rb
- [ ] library/bigdecimal/modulo_spec.rb
- [ ] library/bigdecimal/mult_spec.rb
- [ ] library/bigdecimal/multiply_spec.rb
- [ ] library/bigdecimal/nan_spec.rb
- [ ] library/bigdecimal/nonzero_spec.rb
- [ ] library/bigdecimal/plus_spec.rb
- [ ] library/bigdecimal/power_spec.rb
- [ ] library/bigdecimal/quo_spec.rb
- [ ] library/bigdecimal/remainder_spec.rb
- [ ] library/bigdecimal/round_spec.rb
- [ ] library/bigdecimal/sign_spec.rb
- [ ] library/bigdecimal/split_spec.rb
- [ ] library/bigdecimal/sqrt_spec.rb
- [ ] library/bigdecimal/sub_spec.rb
- [ ] library/bigdecimal/to_d_spec.rb
- [ ] library/bigdecimal/to_f_spec.rb
- [ ] library/bigdecimal/to_i_spec.rb
- [ ] library/bigdecimal/to_int_spec.rb
- [ ] library/bigdecimal/to_r_spec.rb
- [ ] library/bigdecimal/to_s_spec.rb
- [ ] library/bigdecimal/truncate_spec.rb
- [ ] library/bigdecimal/uminus_spec.rb
- [ ] library/bigdecimal/uplus_spec.rb
- [ ] library/bigdecimal/util_spec.rb
- [ ] library/bigdecimal/zero_spec.rb

### library/cgi/cookie
- [ ] library/cgi/cookie/domain_spec.rb
- [ ] library/cgi/cookie/expires_spec.rb
- [ ] library/cgi/cookie/initialize_spec.rb
- [ ] library/cgi/cookie/name_spec.rb
- [ ] library/cgi/cookie/parse_spec.rb
- [ ] library/cgi/cookie/path_spec.rb
- [ ] library/cgi/cookie/secure_spec.rb
- [ ] library/cgi/cookie/to_s_spec.rb
- [ ] library/cgi/cookie/value_spec.rb

### library/cgi
- [ ] library/cgi/escapeElement_spec.rb
- [ ] library/cgi/escapeHTML_spec.rb
- [ ] library/cgi/escapeURIComponent_spec.rb
- [ ] library/cgi/escape_spec.rb

### library/cgi/htmlextension
- [ ] library/cgi/htmlextension/a_spec.rb
- [ ] library/cgi/htmlextension/base_spec.rb
- [ ] library/cgi/htmlextension/blockquote_spec.rb
- [ ] library/cgi/htmlextension/br_spec.rb
- [ ] library/cgi/htmlextension/caption_spec.rb
- [ ] library/cgi/htmlextension/checkbox_group_spec.rb
- [ ] library/cgi/htmlextension/checkbox_spec.rb
- [ ] library/cgi/htmlextension/doctype_spec.rb
- [ ] library/cgi/htmlextension/file_field_spec.rb
- [ ] library/cgi/htmlextension/form_spec.rb
- [ ] library/cgi/htmlextension/frame_spec.rb
- [ ] library/cgi/htmlextension/frameset_spec.rb
- [ ] library/cgi/htmlextension/hidden_spec.rb
- [ ] library/cgi/htmlextension/html_spec.rb
- [ ] library/cgi/htmlextension/image_button_spec.rb
- [ ] library/cgi/htmlextension/img_spec.rb
- [ ] library/cgi/htmlextension/multipart_form_spec.rb
- [ ] library/cgi/htmlextension/password_field_spec.rb
- [ ] library/cgi/htmlextension/popup_menu_spec.rb
- [ ] library/cgi/htmlextension/radio_button_spec.rb
- [ ] library/cgi/htmlextension/radio_group_spec.rb
- [ ] library/cgi/htmlextension/reset_spec.rb
- [ ] library/cgi/htmlextension/scrolling_list_spec.rb
- [ ] library/cgi/htmlextension/submit_spec.rb
- [ ] library/cgi/htmlextension/text_field_spec.rb
- [ ] library/cgi/htmlextension/textarea_spec.rb

### library/cgi
- [ ] library/cgi/http_header_spec.rb
- [ ] library/cgi/initialize_spec.rb
- [ ] library/cgi/out_spec.rb
- [ ] library/cgi/parse_spec.rb
- [ ] library/cgi/pretty_spec.rb
- [ ] library/cgi/print_spec.rb

### library/cgi/queryextension
- [ ] library/cgi/queryextension/accept_charset_spec.rb
- [ ] library/cgi/queryextension/accept_encoding_spec.rb
- [ ] library/cgi/queryextension/accept_language_spec.rb
- [ ] library/cgi/queryextension/accept_spec.rb
- [ ] library/cgi/queryextension/auth_type_spec.rb
- [ ] library/cgi/queryextension/cache_control_spec.rb
- [ ] library/cgi/queryextension/content_length_spec.rb
- [ ] library/cgi/queryextension/content_type_spec.rb
- [ ] library/cgi/queryextension/cookies_spec.rb
- [ ] library/cgi/queryextension/element_reference_spec.rb
- [ ] library/cgi/queryextension/from_spec.rb
- [ ] library/cgi/queryextension/gateway_interface_spec.rb
- [ ] library/cgi/queryextension/has_key_spec.rb
- [ ] library/cgi/queryextension/host_spec.rb
- [ ] library/cgi/queryextension/include_spec.rb
- [ ] library/cgi/queryextension/key_spec.rb
- [ ] library/cgi/queryextension/keys_spec.rb
- [ ] library/cgi/queryextension/multipart_spec.rb
- [ ] library/cgi/queryextension/negotiate_spec.rb
- [ ] library/cgi/queryextension/params_spec.rb
- [ ] library/cgi/queryextension/path_info_spec.rb
- [ ] library/cgi/queryextension/path_translated_spec.rb
- [ ] library/cgi/queryextension/pragma_spec.rb
- [ ] library/cgi/queryextension/query_string_spec.rb
- [ ] library/cgi/queryextension/raw_cookie2_spec.rb
- [ ] library/cgi/queryextension/raw_cookie_spec.rb
- [ ] library/cgi/queryextension/referer_spec.rb
- [ ] library/cgi/queryextension/remote_addr_spec.rb
- [ ] library/cgi/queryextension/remote_host_spec.rb
- [ ] library/cgi/queryextension/remote_ident_spec.rb
- [ ] library/cgi/queryextension/remote_user_spec.rb
- [ ] library/cgi/queryextension/request_method_spec.rb
- [ ] library/cgi/queryextension/script_name_spec.rb
- [ ] library/cgi/queryextension/server_name_spec.rb
- [ ] library/cgi/queryextension/server_port_spec.rb
- [ ] library/cgi/queryextension/server_protocol_spec.rb
- [ ] library/cgi/queryextension/server_software_spec.rb
- [ ] library/cgi/queryextension/user_agent_spec.rb

### library/cgi
- [ ] library/cgi/rfc1123_date_spec.rb
- [ ] library/cgi/unescapeElement_spec.rb
- [ ] library/cgi/unescapeHTML_spec.rb
- [ ] library/cgi/unescapeURIComponent_spec.rb
- [ ] library/cgi/unescape_spec.rb

### library/coverage
- [ ] library/coverage/peek_result_spec.rb
- [ ] library/coverage/result_spec.rb
- [ ] library/coverage/running_spec.rb
- [ ] library/coverage/start_spec.rb
- [ ] library/coverage/supported_spec.rb

### library/csv/basicwriter
- [ ] library/csv/basicwriter/close_on_terminate_spec.rb
- [ ] library/csv/basicwriter/initialize_spec.rb
- [ ] library/csv/basicwriter/terminate_spec.rb

### library/csv/cell
- [ ] library/csv/cell/data_spec.rb
- [ ] library/csv/cell/initialize_spec.rb

### library/csv
- [ ] library/csv/foreach_spec.rb
- [ ] library/csv/generate_line_spec.rb
- [ ] library/csv/generate_row_spec.rb
- [ ] library/csv/generate_spec.rb

### library/csv/iobuf
- [ ] library/csv/iobuf/close_spec.rb
- [ ] library/csv/iobuf/initialize_spec.rb
- [ ] library/csv/iobuf/read_spec.rb
- [ ] library/csv/iobuf/terminate_spec.rb

### library/csv/ioreader
- [ ] library/csv/ioreader/close_on_terminate_spec.rb
- [ ] library/csv/ioreader/get_row_spec.rb
- [ ] library/csv/ioreader/initialize_spec.rb
- [ ] library/csv/ioreader/terminate_spec.rb

### library/csv
- [ ] library/csv/liberal_parsing_spec.rb
- [ ] library/csv/open_spec.rb
- [ ] library/csv/parse_spec.rb
- [ ] library/csv/read_spec.rb
- [ ] library/csv/readlines_spec.rb

### library/csv/streambuf
- [ ] library/csv/streambuf/add_buf_spec.rb
- [ ] library/csv/streambuf/buf_size_spec.rb
- [ ] library/csv/streambuf/drop_spec.rb
- [ ] library/csv/streambuf/element_reference_spec.rb
- [ ] library/csv/streambuf/get_spec.rb
- [ ] library/csv/streambuf/idx_is_eos_spec.rb
- [ ] library/csv/streambuf/initialize_spec.rb
- [ ] library/csv/streambuf/is_eos_spec.rb
- [ ] library/csv/streambuf/read_spec.rb
- [ ] library/csv/streambuf/rel_buf_spec.rb
- [ ] library/csv/streambuf/terminate_spec.rb

### library/csv/stringreader
- [ ] library/csv/stringreader/get_row_spec.rb
- [ ] library/csv/stringreader/initialize_spec.rb

### library/csv/writer
- [ ] library/csv/writer/add_row_spec.rb
- [ ] library/csv/writer/append_spec.rb
- [ ] library/csv/writer/close_spec.rb
- [ ] library/csv/writer/create_spec.rb
- [ ] library/csv/writer/generate_spec.rb
- [ ] library/csv/writer/initialize_spec.rb
- [ ] library/csv/writer/terminate_spec.rb

### library/date
- [ ] library/date/accessor_spec.rb
- [ ] library/date/add_month_spec.rb
- [ ] library/date/add_spec.rb
- [ ] library/date/ajd_spec.rb
- [ ] library/date/ajd_to_amjd_spec.rb
- [ ] library/date/ajd_to_jd_spec.rb
- [ ] library/date/amjd_spec.rb
- [ ] library/date/amjd_to_ajd_spec.rb
- [ ] library/date/append_spec.rb
- [ ] library/date/asctime_spec.rb
- [ ] library/date/boat_spec.rb
- [ ] library/date/case_compare_spec.rb
- [ ] library/date/civil_spec.rb
- [ ] library/date/commercial_spec.rb
- [ ] library/date/commercial_to_jd_spec.rb
- [ ] library/date/comparison_spec.rb
- [ ] library/date/constants_spec.rb
- [ ] library/date/conversions_spec.rb
- [ ] library/date/ctime_spec.rb
- [ ] library/date/cwday_spec.rb
- [ ] library/date/cweek_spec.rb
- [ ] library/date/cwyear_spec.rb
- [ ] library/date/day_fraction_spec.rb
- [ ] library/date/day_fraction_to_time_spec.rb
- [ ] library/date/day_spec.rb
- [ ] library/date/deconstruct_keys_spec.rb
- [ ] library/date/downto_spec.rb
- [ ] library/date/england_spec.rb
- [ ] library/date/eql_spec.rb

### library/date/format/bag
- [ ] library/date/format/bag/method_missing_spec.rb
- [ ] library/date/format/bag/to_hash_spec.rb

### library/date
- [ ] library/date/friday_spec.rb
- [ ] library/date/gregorian_leap_spec.rb
- [ ] library/date/gregorian_spec.rb
- [ ] library/date/hash_spec.rb

### library/date/infinity
- [ ] library/date/infinity/abs_spec.rb
- [ ] library/date/infinity/coerce_spec.rb
- [ ] library/date/infinity/comparison_spec.rb
- [ ] library/date/infinity/d_spec.rb
- [ ] library/date/infinity/finite_spec.rb
- [ ] library/date/infinity/infinite_spec.rb
- [ ] library/date/infinity/nan_spec.rb
- [ ] library/date/infinity/uminus_spec.rb
- [ ] library/date/infinity/uplus_spec.rb
- [ ] library/date/infinity/zero_spec.rb

### library/date
- [ ] library/date/infinity_spec.rb
- [ ] library/date/inspect_spec.rb
- [ ] library/date/iso8601_spec.rb
- [ ] library/date/italy_spec.rb
- [ ] library/date/jd_spec.rb
- [ ] library/date/jd_to_ajd_spec.rb
- [ ] library/date/jd_to_civil_spec.rb
- [ ] library/date/jd_to_commercial_spec.rb
- [ ] library/date/jd_to_ld_spec.rb
- [ ] library/date/jd_to_mjd_spec.rb
- [ ] library/date/jd_to_ordinal_spec.rb
- [ ] library/date/jd_to_wday_spec.rb
- [ ] library/date/julian_leap_spec.rb
- [ ] library/date/julian_spec.rb
- [ ] library/date/ld_spec.rb
- [ ] library/date/ld_to_jd_spec.rb
- [ ] library/date/leap_spec.rb
- [ ] library/date/mday_spec.rb
- [ ] library/date/minus_month_spec.rb
- [ ] library/date/minus_spec.rb
- [ ] library/date/mjd_spec.rb
- [ ] library/date/mjd_to_jd_spec.rb
- [ ] library/date/mon_spec.rb
- [ ] library/date/monday_spec.rb
- [ ] library/date/month_spec.rb
- [ ] library/date/new_spec.rb
- [ ] library/date/new_start_spec.rb
- [ ] library/date/next_day_spec.rb
- [ ] library/date/next_month_spec.rb
- [ ] library/date/next_spec.rb
- [ ] library/date/next_year_spec.rb
- [ ] library/date/ordinal_spec.rb
- [ ] library/date/ordinal_to_jd_spec.rb
- [ ] library/date/parse_spec.rb
- [ ] library/date/plus_spec.rb
- [ ] library/date/prev_day_spec.rb
- [ ] library/date/prev_month_spec.rb
- [ ] library/date/prev_year_spec.rb
- [ ] library/date/relationship_spec.rb
- [ ] library/date/rfc3339_spec.rb
- [ ] library/date/right_shift_spec.rb
- [ ] library/date/saturday_spec.rb
- [ ] library/date/start_spec.rb
- [ ] library/date/step_spec.rb
- [ ] library/date/strftime_spec.rb
- [ ] library/date/strptime_spec.rb
- [ ] library/date/succ_spec.rb
- [ ] library/date/sunday_spec.rb
- [ ] library/date/thursday_spec.rb

### library/date/time
- [ ] library/date/time/to_date_spec.rb

### library/date
- [ ] library/date/time_to_day_fraction_spec.rb
- [ ] library/date/to_s_spec.rb
- [ ] library/date/today_spec.rb
- [ ] library/date/tuesday_spec.rb
- [ ] library/date/upto_spec.rb
- [ ] library/date/valid_civil_spec.rb
- [ ] library/date/valid_commercial_spec.rb
- [ ] library/date/valid_date_spec.rb
- [ ] library/date/valid_jd_spec.rb
- [ ] library/date/valid_ordinal_spec.rb
- [ ] library/date/valid_time_spec.rb
- [ ] library/date/wday_spec.rb
- [ ] library/date/wednesday_spec.rb
- [ ] library/date/yday_spec.rb
- [ ] library/date/year_spec.rb
- [ ] library/date/zone_to_diff_spec.rb

### library/datetime
- [ ] library/datetime/_strptime_spec.rb
- [ ] library/datetime/add_spec.rb
- [ ] library/datetime/civil_spec.rb
- [ ] library/datetime/commercial_spec.rb
- [ ] library/datetime/deconstruct_keys_spec.rb
- [ ] library/datetime/hour_spec.rb
- [ ] library/datetime/httpdate_spec.rb
- [ ] library/datetime/iso8601_spec.rb
- [ ] library/datetime/jd_spec.rb
- [ ] library/datetime/jisx0301_spec.rb
- [ ] library/datetime/min_spec.rb
- [ ] library/datetime/minute_spec.rb
- [ ] library/datetime/new_offset_spec.rb
- [ ] library/datetime/new_spec.rb
- [ ] library/datetime/now_spec.rb
- [ ] library/datetime/offset_spec.rb
- [ ] library/datetime/ordinal_spec.rb
- [ ] library/datetime/parse_spec.rb
- [ ] library/datetime/rfc2822_spec.rb
- [ ] library/datetime/rfc3339_spec.rb
- [ ] library/datetime/rfc822_spec.rb
- [ ] library/datetime/sec_fraction_spec.rb
- [ ] library/datetime/sec_spec.rb
- [ ] library/datetime/second_fraction_spec.rb
- [ ] library/datetime/second_spec.rb
- [ ] library/datetime/strftime_spec.rb
- [ ] library/datetime/strptime_spec.rb
- [ ] library/datetime/subtract_spec.rb

### library/datetime/time
- [ ] library/datetime/time/to_datetime_spec.rb

### library/datetime
- [ ] library/datetime/to_date_spec.rb
- [ ] library/datetime/to_datetime_spec.rb
- [ ] library/datetime/to_s_spec.rb
- [ ] library/datetime/to_time_spec.rb
- [ ] library/datetime/xmlschema_spec.rb
- [ ] library/datetime/yday_spec.rb
- [ ] library/datetime/zone_spec.rb

### library/delegate/delegate_class
- [ ] library/delegate/delegate_class/instance_method_spec.rb
- [ ] library/delegate/delegate_class/instance_methods_spec.rb
- [ ] library/delegate/delegate_class/private_instance_methods_spec.rb
- [ ] library/delegate/delegate_class/protected_instance_methods_spec.rb
- [ ] library/delegate/delegate_class/public_instance_methods_spec.rb
- [ ] library/delegate/delegate_class/respond_to_missing_spec.rb

### library/delegate/delegator
- [ ] library/delegate/delegator/case_compare_spec.rb
- [ ] library/delegate/delegator/compare_spec.rb
- [ ] library/delegate/delegator/complement_spec.rb
- [ ] library/delegate/delegator/eql_spec.rb
- [ ] library/delegate/delegator/equal_spec.rb
- [ ] library/delegate/delegator/equal_value_spec.rb
- [ ] library/delegate/delegator/frozen_spec.rb
- [ ] library/delegate/delegator/hash_spec.rb
- [ ] library/delegate/delegator/marshal_spec.rb
- [ ] library/delegate/delegator/method_spec.rb
- [ ] library/delegate/delegator/methods_spec.rb
- [ ] library/delegate/delegator/not_equal_spec.rb
- [ ] library/delegate/delegator/not_spec.rb
- [ ] library/delegate/delegator/private_methods_spec.rb
- [ ] library/delegate/delegator/protected_methods_spec.rb
- [ ] library/delegate/delegator/public_methods_spec.rb
- [ ] library/delegate/delegator/send_spec.rb
- [ ] library/delegate/delegator/taint_spec.rb
- [ ] library/delegate/delegator/tap_spec.rb
- [ ] library/delegate/delegator/trust_spec.rb
- [ ] library/delegate/delegator/untaint_spec.rb
- [ ] library/delegate/delegator/untrust_spec.rb

### library/digest
- [ ] library/digest/bubblebabble_spec.rb
- [ ] library/digest/hexencode_spec.rb

### library/digest/instance
- [ ] library/digest/instance/append_spec.rb
- [ ] library/digest/instance/new_spec.rb
- [ ] library/digest/instance/update_spec.rb

### library/digest/md5
- [ ] library/digest/md5/append_spec.rb
- [ ] library/digest/md5/block_length_spec.rb
- [ ] library/digest/md5/digest_bang_spec.rb
- [ ] library/digest/md5/digest_length_spec.rb
- [ ] library/digest/md5/digest_spec.rb
- [ ] library/digest/md5/equal_spec.rb
- [ ] library/digest/md5/file_spec.rb
- [ ] library/digest/md5/hexdigest_bang_spec.rb
- [ ] library/digest/md5/hexdigest_spec.rb
- [ ] library/digest/md5/inspect_spec.rb
- [ ] library/digest/md5/length_spec.rb
- [ ] library/digest/md5/reset_spec.rb
- [ ] library/digest/md5/size_spec.rb
- [ ] library/digest/md5/to_s_spec.rb
- [ ] library/digest/md5/update_spec.rb

### library/digest/sha1
- [ ] library/digest/sha1/digest_spec.rb
- [ ] library/digest/sha1/file_spec.rb

### library/digest/sha2
- [ ] library/digest/sha2/hexdigest_spec.rb

### library/digest/sha256
- [ ] library/digest/sha256/append_spec.rb
- [ ] library/digest/sha256/block_length_spec.rb
- [ ] library/digest/sha256/digest_bang_spec.rb
- [ ] library/digest/sha256/digest_length_spec.rb
- [ ] library/digest/sha256/digest_spec.rb
- [ ] library/digest/sha256/equal_spec.rb
- [ ] library/digest/sha256/file_spec.rb
- [ ] library/digest/sha256/hexdigest_bang_spec.rb
- [ ] library/digest/sha256/hexdigest_spec.rb
- [ ] library/digest/sha256/inspect_spec.rb
- [ ] library/digest/sha256/length_spec.rb
- [ ] library/digest/sha256/reset_spec.rb
- [ ] library/digest/sha256/size_spec.rb
- [ ] library/digest/sha256/to_s_spec.rb
- [ ] library/digest/sha256/update_spec.rb

### library/digest/sha384
- [ ] library/digest/sha384/append_spec.rb
- [ ] library/digest/sha384/block_length_spec.rb
- [ ] library/digest/sha384/digest_bang_spec.rb
- [ ] library/digest/sha384/digest_length_spec.rb
- [ ] library/digest/sha384/digest_spec.rb
- [ ] library/digest/sha384/equal_spec.rb
- [ ] library/digest/sha384/file_spec.rb
- [ ] library/digest/sha384/hexdigest_bang_spec.rb
- [ ] library/digest/sha384/hexdigest_spec.rb
- [ ] library/digest/sha384/inspect_spec.rb
- [ ] library/digest/sha384/length_spec.rb
- [ ] library/digest/sha384/reset_spec.rb
- [ ] library/digest/sha384/size_spec.rb
- [ ] library/digest/sha384/to_s_spec.rb
- [ ] library/digest/sha384/update_spec.rb

### library/digest/sha512
- [ ] library/digest/sha512/append_spec.rb
- [ ] library/digest/sha512/block_length_spec.rb
- [ ] library/digest/sha512/digest_bang_spec.rb
- [ ] library/digest/sha512/digest_length_spec.rb
- [ ] library/digest/sha512/digest_spec.rb
- [ ] library/digest/sha512/equal_spec.rb
- [ ] library/digest/sha512/file_spec.rb
- [ ] library/digest/sha512/hexdigest_bang_spec.rb
- [ ] library/digest/sha512/hexdigest_spec.rb
- [ ] library/digest/sha512/inspect_spec.rb
- [ ] library/digest/sha512/length_spec.rb
- [ ] library/digest/sha512/reset_spec.rb
- [ ] library/digest/sha512/size_spec.rb
- [ ] library/digest/sha512/to_s_spec.rb
- [ ] library/digest/sha512/update_spec.rb

### library/drb
- [ ] library/drb/start_service_spec.rb

### library/erb
- [ ] library/erb/def_class_spec.rb
- [ ] library/erb/def_method_spec.rb
- [ ] library/erb/def_module_spec.rb

### library/erb/defmethod
- [ ] library/erb/defmethod/def_erb_method_spec.rb

### library/erb
- [ ] library/erb/filename_spec.rb
- [ ] library/erb/new_spec.rb
- [ ] library/erb/result_spec.rb
- [ ] library/erb/run_spec.rb
- [ ] library/erb/src_spec.rb

### library/erb/util
- [ ] library/erb/util/h_spec.rb
- [ ] library/erb/util/html_escape_spec.rb
- [ ] library/erb/util/u_spec.rb
- [ ] library/erb/util/url_encode_spec.rb

### library/etc
- [ ] library/etc/confstr_spec.rb
- [ ] library/etc/endgrent_spec.rb
- [ ] library/etc/endpwent_spec.rb
- [ ] library/etc/getgrent_spec.rb
- [ ] library/etc/getgrgid_spec.rb
- [ ] library/etc/getgrnam_spec.rb
- [ ] library/etc/getlogin_spec.rb
- [ ] library/etc/getpwent_spec.rb
- [ ] library/etc/getpwnam_spec.rb
- [ ] library/etc/getpwuid_spec.rb
- [ ] library/etc/group_spec.rb
- [ ] library/etc/nprocessors_spec.rb
- [ ] library/etc/passwd_spec.rb
- [ ] library/etc/struct_group_spec.rb
- [ ] library/etc/struct_passwd_spec.rb
- [ ] library/etc/sysconf_spec.rb
- [ ] library/etc/sysconfdir_spec.rb
- [ ] library/etc/systmpdir_spec.rb
- [ ] library/etc/uname_spec.rb

### library/expect
- [ ] library/expect/expect_spec.rb

### library/fiddle/handle
- [ ] library/fiddle/handle/initialize_spec.rb

### library/find
- [ ] library/find/find_spec.rb
- [ ] library/find/prune_spec.rb

### library/getoptlong
- [ ] library/getoptlong/each_option_spec.rb
- [ ] library/getoptlong/each_spec.rb
- [ ] library/getoptlong/error_message_spec.rb
- [ ] library/getoptlong/get_option_spec.rb
- [ ] library/getoptlong/get_spec.rb
- [ ] library/getoptlong/initialize_spec.rb
- [ ] library/getoptlong/ordering_spec.rb
- [ ] library/getoptlong/set_options_spec.rb
- [ ] library/getoptlong/terminate_spec.rb
- [ ] library/getoptlong/terminated_spec.rb

### library/io-wait
- [ ] library/io-wait/wait_readable_spec.rb
- [ ] library/io-wait/wait_spec.rb
- [ ] library/io-wait/wait_writable_spec.rb

### library/ipaddr
- [ ] library/ipaddr/hton_spec.rb
- [ ] library/ipaddr/ipv4_conversion_spec.rb
- [ ] library/ipaddr/new_spec.rb
- [ ] library/ipaddr/operator_spec.rb
- [ ] library/ipaddr/reverse_spec.rb
- [ ] library/ipaddr/to_s_spec.rb

### library/irb
- [ ] library/irb/irb_spec.rb

### library/logger/device
- [ ] library/logger/device/close_spec.rb
- [ ] library/logger/device/new_spec.rb
- [ ] library/logger/device/write_spec.rb

### library/logger/logger
- [ ] library/logger/logger/add_spec.rb
- [ ] library/logger/logger/close_spec.rb
- [ ] library/logger/logger/datetime_format_spec.rb
- [ ] library/logger/logger/debug_spec.rb
- [ ] library/logger/logger/error_spec.rb
- [ ] library/logger/logger/fatal_spec.rb
- [ ] library/logger/logger/info_spec.rb
- [ ] library/logger/logger/new_spec.rb
- [ ] library/logger/logger/unknown_spec.rb
- [ ] library/logger/logger/warn_spec.rb

### library/logger
- [ ] library/logger/severity_spec.rb

### library/matrix
- [ ] library/matrix/I_spec.rb
- [ ] library/matrix/antisymmetric_spec.rb
- [ ] library/matrix/build_spec.rb
- [ ] library/matrix/clone_spec.rb
- [ ] library/matrix/coerce_spec.rb
- [ ] library/matrix/collect_spec.rb
- [ ] library/matrix/column_size_spec.rb
- [ ] library/matrix/column_spec.rb
- [ ] library/matrix/column_vector_spec.rb
- [ ] library/matrix/column_vectors_spec.rb
- [ ] library/matrix/columns_spec.rb
- [ ] library/matrix/conj_spec.rb
- [ ] library/matrix/conjugate_spec.rb
- [ ] library/matrix/constructor_spec.rb
- [ ] library/matrix/det_spec.rb
- [ ] library/matrix/determinant_spec.rb
- [ ] library/matrix/diagonal_spec.rb
- [ ] library/matrix/divide_spec.rb
- [ ] library/matrix/each_spec.rb
- [ ] library/matrix/each_with_index_spec.rb

### library/matrix/eigenvalue_decomposition
- [ ] library/matrix/eigenvalue_decomposition/eigenvalue_matrix_spec.rb
- [ ] library/matrix/eigenvalue_decomposition/eigenvalues_spec.rb
- [ ] library/matrix/eigenvalue_decomposition/eigenvector_matrix_spec.rb
- [ ] library/matrix/eigenvalue_decomposition/eigenvectors_spec.rb
- [ ] library/matrix/eigenvalue_decomposition/initialize_spec.rb
- [ ] library/matrix/eigenvalue_decomposition/to_a_spec.rb

### library/matrix
- [ ] library/matrix/element_reference_spec.rb
- [ ] library/matrix/empty_spec.rb
- [ ] library/matrix/eql_spec.rb
- [ ] library/matrix/equal_value_spec.rb
- [ ] library/matrix/exponent_spec.rb
- [ ] library/matrix/find_index_spec.rb
- [ ] library/matrix/hash_spec.rb
- [ ] library/matrix/hermitian_spec.rb
- [ ] library/matrix/identity_spec.rb
- [ ] library/matrix/imag_spec.rb
- [ ] library/matrix/imaginary_spec.rb
- [ ] library/matrix/inspect_spec.rb
- [ ] library/matrix/inv_spec.rb
- [ ] library/matrix/inverse_from_spec.rb
- [ ] library/matrix/inverse_spec.rb
- [ ] library/matrix/lower_triangular_spec.rb

### library/matrix/lup_decomposition
- [ ] library/matrix/lup_decomposition/determinant_spec.rb
- [ ] library/matrix/lup_decomposition/initialize_spec.rb
- [ ] library/matrix/lup_decomposition/l_spec.rb
- [ ] library/matrix/lup_decomposition/p_spec.rb
- [ ] library/matrix/lup_decomposition/solve_spec.rb
- [ ] library/matrix/lup_decomposition/to_a_spec.rb
- [ ] library/matrix/lup_decomposition/u_spec.rb

### library/matrix
- [ ] library/matrix/map_spec.rb
- [ ] library/matrix/minor_spec.rb
- [ ] library/matrix/minus_spec.rb
- [ ] library/matrix/multiply_spec.rb
- [ ] library/matrix/new_spec.rb
- [ ] library/matrix/normal_spec.rb
- [ ] library/matrix/orthogonal_spec.rb
- [ ] library/matrix/permutation_spec.rb
- [ ] library/matrix/plus_spec.rb
- [ ] library/matrix/rank_spec.rb
- [ ] library/matrix/real_spec.rb
- [ ] library/matrix/rect_spec.rb
- [ ] library/matrix/rectangular_spec.rb
- [ ] library/matrix/regular_spec.rb
- [ ] library/matrix/round_spec.rb
- [ ] library/matrix/row_size_spec.rb
- [ ] library/matrix/row_spec.rb
- [ ] library/matrix/row_vector_spec.rb
- [ ] library/matrix/row_vectors_spec.rb
- [ ] library/matrix/rows_spec.rb

### library/matrix/scalar
- [ ] library/matrix/scalar/Fail_spec.rb
- [ ] library/matrix/scalar/Raise_spec.rb
- [ ] library/matrix/scalar/divide_spec.rb
- [ ] library/matrix/scalar/exponent_spec.rb
- [ ] library/matrix/scalar/included_spec.rb
- [ ] library/matrix/scalar/initialize_spec.rb
- [ ] library/matrix/scalar/minus_spec.rb
- [ ] library/matrix/scalar/multiply_spec.rb
- [ ] library/matrix/scalar/plus_spec.rb

### library/matrix
- [ ] library/matrix/scalar_spec.rb
- [ ] library/matrix/singular_spec.rb
- [ ] library/matrix/square_spec.rb
- [ ] library/matrix/symmetric_spec.rb
- [ ] library/matrix/t_spec.rb
- [ ] library/matrix/to_a_spec.rb
- [ ] library/matrix/to_s_spec.rb
- [ ] library/matrix/tr_spec.rb
- [ ] library/matrix/trace_spec.rb
- [ ] library/matrix/transpose_spec.rb
- [ ] library/matrix/unit_spec.rb
- [ ] library/matrix/unitary_spec.rb
- [ ] library/matrix/upper_triangular_spec.rb

### library/matrix/vector
- [ ] library/matrix/vector/cross_product_spec.rb
- [ ] library/matrix/vector/each2_spec.rb
- [ ] library/matrix/vector/eql_spec.rb
- [ ] library/matrix/vector/inner_product_spec.rb
- [ ] library/matrix/vector/normalize_spec.rb

### library/matrix
- [ ] library/matrix/zero_spec.rb

### library/mkmf
- [ ] library/mkmf/mkmf_spec.rb

### library/monitor
- [ ] library/monitor/enter_spec.rb
- [ ] library/monitor/exit_spec.rb
- [ ] library/monitor/mon_initialize_spec.rb
- [ ] library/monitor/new_cond_spec.rb
- [ ] library/monitor/synchronize_spec.rb
- [ ] library/monitor/try_enter_spec.rb

### library/net-ftp
- [ ] library/net-ftp/FTPError_spec.rb
- [ ] library/net-ftp/FTPPermError_spec.rb
- [ ] library/net-ftp/FTPProtoError_spec.rb
- [ ] library/net-ftp/FTPReplyError_spec.rb
- [ ] library/net-ftp/FTPTempError_spec.rb
- [ ] library/net-ftp/abort_spec.rb
- [ ] library/net-ftp/acct_spec.rb
- [ ] library/net-ftp/binary_spec.rb
- [ ] library/net-ftp/chdir_spec.rb
- [ ] library/net-ftp/close_spec.rb
- [ ] library/net-ftp/closed_spec.rb
- [ ] library/net-ftp/connect_spec.rb
- [ ] library/net-ftp/debug_mode_spec.rb
- [ ] library/net-ftp/default_passive_spec.rb
- [ ] library/net-ftp/delete_spec.rb
- [ ] library/net-ftp/dir_spec.rb
- [ ] library/net-ftp/get_spec.rb
- [ ] library/net-ftp/getbinaryfile_spec.rb
- [ ] library/net-ftp/getdir_spec.rb
- [ ] library/net-ftp/gettextfile_spec.rb
- [ ] library/net-ftp/help_spec.rb
- [ ] library/net-ftp/initialize_spec.rb
- [ ] library/net-ftp/last_response_code_spec.rb
- [ ] library/net-ftp/last_response_spec.rb
- [ ] library/net-ftp/lastresp_spec.rb
- [ ] library/net-ftp/list_spec.rb
- [ ] library/net-ftp/login_spec.rb
- [ ] library/net-ftp/ls_spec.rb
- [ ] library/net-ftp/mdtm_spec.rb
- [ ] library/net-ftp/mkdir_spec.rb
- [ ] library/net-ftp/mtime_spec.rb
- [ ] library/net-ftp/nlst_spec.rb
- [ ] library/net-ftp/noop_spec.rb
- [ ] library/net-ftp/open_spec.rb
- [ ] library/net-ftp/passive_spec.rb
- [ ] library/net-ftp/put_spec.rb
- [ ] library/net-ftp/putbinaryfile_spec.rb
- [ ] library/net-ftp/puttextfile_spec.rb
- [ ] library/net-ftp/pwd_spec.rb
- [ ] library/net-ftp/quit_spec.rb
- [ ] library/net-ftp/rename_spec.rb
- [ ] library/net-ftp/resume_spec.rb
- [ ] library/net-ftp/retrbinary_spec.rb
- [ ] library/net-ftp/retrlines_spec.rb
- [ ] library/net-ftp/return_code_spec.rb
- [ ] library/net-ftp/rmdir_spec.rb
- [ ] library/net-ftp/sendcmd_spec.rb
- [ ] library/net-ftp/set_socket_spec.rb
- [ ] library/net-ftp/site_spec.rb
- [ ] library/net-ftp/size_spec.rb
- [ ] library/net-ftp/status_spec.rb
- [ ] library/net-ftp/storbinary_spec.rb
- [ ] library/net-ftp/storlines_spec.rb
- [ ] library/net-ftp/system_spec.rb
- [ ] library/net-ftp/voidcmd_spec.rb
- [ ] library/net-ftp/welcome_spec.rb

### library/net-http
- [ ] library/net-http/HTTPBadResponse_spec.rb
- [ ] library/net-http/HTTPClientExcepton_spec.rb
- [ ] library/net-http/HTTPError_spec.rb
- [ ] library/net-http/HTTPFatalError_spec.rb
- [ ] library/net-http/HTTPHeaderSyntaxError_spec.rb
- [ ] library/net-http/HTTPRetriableError_spec.rb
- [ ] library/net-http/HTTPServerException_spec.rb

### library/net-http/http
- [ ] library/net-http/http/Proxy_spec.rb
- [ ] library/net-http/http/active_spec.rb
- [ ] library/net-http/http/address_spec.rb
- [ ] library/net-http/http/close_on_empty_response_spec.rb
- [ ] library/net-http/http/copy_spec.rb
- [ ] library/net-http/http/default_port_spec.rb
- [ ] library/net-http/http/delete_spec.rb
- [ ] library/net-http/http/finish_spec.rb
- [ ] library/net-http/http/get2_spec.rb
- [ ] library/net-http/http/get_print_spec.rb
- [ ] library/net-http/http/get_response_spec.rb
- [ ] library/net-http/http/get_spec.rb
- [ ] library/net-http/http/head2_spec.rb
- [ ] library/net-http/http/head_spec.rb
- [ ] library/net-http/http/http_default_port_spec.rb
- [ ] library/net-http/http/https_default_port_spec.rb
- [ ] library/net-http/http/initialize_spec.rb
- [ ] library/net-http/http/inspect_spec.rb
- [ ] library/net-http/http/is_version_1_1_spec.rb
- [ ] library/net-http/http/is_version_1_2_spec.rb
- [ ] library/net-http/http/lock_spec.rb
- [ ] library/net-http/http/mkcol_spec.rb
- [ ] library/net-http/http/move_spec.rb
- [ ] library/net-http/http/new_spec.rb
- [ ] library/net-http/http/newobj_spec.rb
- [ ] library/net-http/http/open_timeout_spec.rb
- [ ] library/net-http/http/options_spec.rb
- [ ] library/net-http/http/port_spec.rb
- [ ] library/net-http/http/post2_spec.rb
- [ ] library/net-http/http/post_form_spec.rb
- [ ] library/net-http/http/post_spec.rb
- [ ] library/net-http/http/propfind_spec.rb
- [ ] library/net-http/http/proppatch_spec.rb
- [ ] library/net-http/http/proxy_address_spec.rb
- [ ] library/net-http/http/proxy_class_spec.rb
- [ ] library/net-http/http/proxy_pass_spec.rb
- [ ] library/net-http/http/proxy_port_spec.rb
- [ ] library/net-http/http/proxy_user_spec.rb
- [ ] library/net-http/http/put2_spec.rb
- [ ] library/net-http/http/put_spec.rb
- [ ] library/net-http/http/read_timeout_spec.rb
- [ ] library/net-http/http/request_get_spec.rb
- [ ] library/net-http/http/request_head_spec.rb
- [ ] library/net-http/http/request_post_spec.rb
- [ ] library/net-http/http/request_put_spec.rb
- [ ] library/net-http/http/request_spec.rb
- [ ] library/net-http/http/request_types_spec.rb
- [ ] library/net-http/http/send_request_spec.rb
- [ ] library/net-http/http/set_debug_output_spec.rb
- [ ] library/net-http/http/socket_type_spec.rb
- [ ] library/net-http/http/start_spec.rb
- [ ] library/net-http/http/started_spec.rb
- [ ] library/net-http/http/trace_spec.rb
- [ ] library/net-http/http/unlock_spec.rb
- [ ] library/net-http/http/use_ssl_spec.rb
- [ ] library/net-http/http/version_1_1_spec.rb
- [ ] library/net-http/http/version_1_2_spec.rb

### library/net-http/httpexceptions
- [ ] library/net-http/httpexceptions/initialize_spec.rb
- [ ] library/net-http/httpexceptions/response_spec.rb

### library/net-http/httpgenericrequest
- [ ] library/net-http/httpgenericrequest/body_exist_spec.rb
- [ ] library/net-http/httpgenericrequest/body_spec.rb
- [ ] library/net-http/httpgenericrequest/body_stream_spec.rb
- [ ] library/net-http/httpgenericrequest/exec_spec.rb
- [ ] library/net-http/httpgenericrequest/inspect_spec.rb
- [ ] library/net-http/httpgenericrequest/method_spec.rb
- [ ] library/net-http/httpgenericrequest/path_spec.rb
- [ ] library/net-http/httpgenericrequest/request_body_permitted_spec.rb
- [ ] library/net-http/httpgenericrequest/response_body_permitted_spec.rb
- [ ] library/net-http/httpgenericrequest/set_body_internal_spec.rb

### library/net-http/httpheader
- [ ] library/net-http/httpheader/add_field_spec.rb
- [ ] library/net-http/httpheader/basic_auth_spec.rb
- [ ] library/net-http/httpheader/canonical_each_spec.rb
- [ ] library/net-http/httpheader/chunked_spec.rb
- [ ] library/net-http/httpheader/content_length_spec.rb
- [ ] library/net-http/httpheader/content_range_spec.rb
- [ ] library/net-http/httpheader/content_type_spec.rb
- [ ] library/net-http/httpheader/delete_spec.rb
- [ ] library/net-http/httpheader/each_capitalized_name_spec.rb
- [ ] library/net-http/httpheader/each_capitalized_spec.rb
- [ ] library/net-http/httpheader/each_header_spec.rb
- [ ] library/net-http/httpheader/each_key_spec.rb
- [ ] library/net-http/httpheader/each_name_spec.rb
- [ ] library/net-http/httpheader/each_spec.rb
- [ ] library/net-http/httpheader/each_value_spec.rb
- [ ] library/net-http/httpheader/element_reference_spec.rb
- [ ] library/net-http/httpheader/element_set_spec.rb
- [ ] library/net-http/httpheader/fetch_spec.rb
- [ ] library/net-http/httpheader/form_data_spec.rb
- [ ] library/net-http/httpheader/get_fields_spec.rb
- [ ] library/net-http/httpheader/initialize_http_header_spec.rb
- [ ] library/net-http/httpheader/key_spec.rb
- [ ] library/net-http/httpheader/length_spec.rb
- [ ] library/net-http/httpheader/main_type_spec.rb
- [ ] library/net-http/httpheader/proxy_basic_auth_spec.rb
- [ ] library/net-http/httpheader/range_length_spec.rb
- [ ] library/net-http/httpheader/range_spec.rb
- [ ] library/net-http/httpheader/set_content_type_spec.rb
- [ ] library/net-http/httpheader/set_form_data_spec.rb
- [ ] library/net-http/httpheader/set_range_spec.rb
- [ ] library/net-http/httpheader/size_spec.rb
- [ ] library/net-http/httpheader/sub_type_spec.rb
- [ ] library/net-http/httpheader/to_hash_spec.rb
- [ ] library/net-http/httpheader/type_params_spec.rb

### library/net-http/httprequest
- [ ] library/net-http/httprequest/initialize_spec.rb

### library/net-http/httpresponse
- [ ] library/net-http/httpresponse/body_permitted_spec.rb
- [ ] library/net-http/httpresponse/body_spec.rb
- [ ] library/net-http/httpresponse/code_spec.rb
- [ ] library/net-http/httpresponse/code_type_spec.rb
- [ ] library/net-http/httpresponse/entity_spec.rb
- [ ] library/net-http/httpresponse/error_spec.rb
- [ ] library/net-http/httpresponse/error_type_spec.rb
- [ ] library/net-http/httpresponse/exception_type_spec.rb
- [ ] library/net-http/httpresponse/header_spec.rb
- [ ] library/net-http/httpresponse/http_version_spec.rb
- [ ] library/net-http/httpresponse/initialize_spec.rb
- [ ] library/net-http/httpresponse/inspect_spec.rb
- [ ] library/net-http/httpresponse/message_spec.rb
- [ ] library/net-http/httpresponse/msg_spec.rb
- [ ] library/net-http/httpresponse/read_body_spec.rb
- [ ] library/net-http/httpresponse/read_header_spec.rb
- [ ] library/net-http/httpresponse/read_new_spec.rb
- [ ] library/net-http/httpresponse/reading_body_spec.rb
- [ ] library/net-http/httpresponse/response_spec.rb
- [ ] library/net-http/httpresponse/value_spec.rb

### library/objectspace
- [ ] library/objectspace/dump_all_spec.rb
- [ ] library/objectspace/dump_spec.rb
- [ ] library/objectspace/memsize_of_all_spec.rb
- [ ] library/objectspace/memsize_of_spec.rb
- [ ] library/objectspace/reachable_objects_from_spec.rb
- [ ] library/objectspace/trace_object_allocations_spec.rb
- [ ] library/objectspace/trace_spec.rb

### library/observer
- [ ] library/observer/add_observer_spec.rb
- [ ] library/observer/count_observers_spec.rb
- [ ] library/observer/delete_observer_spec.rb
- [ ] library/observer/delete_observers_spec.rb
- [ ] library/observer/notify_observers_spec.rb

### library/open3
- [ ] library/open3/capture2_spec.rb
- [ ] library/open3/capture2e_spec.rb
- [ ] library/open3/capture3_spec.rb
- [ ] library/open3/pipeline_r_spec.rb
- [ ] library/open3/pipeline_rw_spec.rb
- [ ] library/open3/pipeline_spec.rb
- [ ] library/open3/pipeline_start_spec.rb
- [ ] library/open3/pipeline_w_spec.rb
- [ ] library/open3/popen2_spec.rb
- [ ] library/open3/popen2e_spec.rb
- [ ] library/open3/popen3_spec.rb

### library/openssl
- [ ] library/openssl/cipher_spec.rb

### library/openssl/digest
- [ ] library/openssl/digest/append_spec.rb
- [ ] library/openssl/digest/block_length_spec.rb
- [ ] library/openssl/digest/digest_length_spec.rb
- [ ] library/openssl/digest/digest_spec.rb
- [ ] library/openssl/digest/initialize_spec.rb
- [ ] library/openssl/digest/name_spec.rb
- [ ] library/openssl/digest/reset_spec.rb
- [ ] library/openssl/digest/update_spec.rb

### library/openssl
- [ ] library/openssl/fixed_length_secure_compare_spec.rb

### library/openssl/hmac
- [ ] library/openssl/hmac/digest_spec.rb
- [ ] library/openssl/hmac/hexdigest_spec.rb

### library/openssl/kdf
- [ ] library/openssl/kdf/pbkdf2_hmac_spec.rb
- [ ] library/openssl/kdf/scrypt_spec.rb

### library/openssl/random
- [ ] library/openssl/random/pseudo_bytes_spec.rb
- [ ] library/openssl/random/random_bytes_spec.rb

### library/openssl
- [ ] library/openssl/secure_compare_spec.rb

### library/openssl/x509/name
- [ ] library/openssl/x509/name/parse_spec.rb

### library/openssl/x509/store
- [ ] library/openssl/x509/store/verify_spec.rb

### library/openstruct
- [ ] library/openstruct/delete_field_spec.rb
- [ ] library/openstruct/element_reference_spec.rb
- [ ] library/openstruct/element_set_spec.rb
- [ ] library/openstruct/equal_value_spec.rb
- [ ] library/openstruct/frozen_spec.rb
- [ ] library/openstruct/initialize_spec.rb
- [ ] library/openstruct/inspect_spec.rb
- [ ] library/openstruct/marshal_dump_spec.rb
- [ ] library/openstruct/marshal_load_spec.rb
- [ ] library/openstruct/method_missing_spec.rb
- [ ] library/openstruct/new_spec.rb
- [ ] library/openstruct/to_h_spec.rb
- [ ] library/openstruct/to_s_spec.rb

### library/optionparser
- [ ] library/optionparser/order_spec.rb
- [ ] library/optionparser/parse_spec.rb

### library/pathname
- [ ] library/pathname/absolute_spec.rb
- [ ] library/pathname/birthtime_spec.rb
- [ ] library/pathname/divide_spec.rb
- [ ] library/pathname/empty_spec.rb
- [ ] library/pathname/equal_value_spec.rb
- [ ] library/pathname/glob_spec.rb
- [ ] library/pathname/hash_spec.rb
- [ ] library/pathname/inspect_spec.rb
- [ ] library/pathname/join_spec.rb
- [ ] library/pathname/new_spec.rb
- [ ] library/pathname/parent_spec.rb
- [ ] library/pathname/pathname_spec.rb
- [ ] library/pathname/plus_spec.rb
- [ ] library/pathname/realdirpath_spec.rb
- [ ] library/pathname/realpath_spec.rb
- [ ] library/pathname/relative_path_from_spec.rb
- [ ] library/pathname/relative_spec.rb
- [ ] library/pathname/root_spec.rb
- [ ] library/pathname/sub_spec.rb

### library/pp
- [ ] library/pp/pp_spec.rb

### library/prime
- [ ] library/prime/each_spec.rb
- [ ] library/prime/instance_spec.rb
- [ ] library/prime/int_from_prime_division_spec.rb

### library/prime/integer
- [ ] library/prime/integer/each_prime_spec.rb
- [ ] library/prime/integer/from_prime_division_spec.rb
- [ ] library/prime/integer/prime_division_spec.rb
- [ ] library/prime/integer/prime_spec.rb

### library/prime
- [ ] library/prime/next_spec.rb
- [ ] library/prime/prime_division_spec.rb
- [ ] library/prime/prime_spec.rb
- [ ] library/prime/succ_spec.rb

### library/random/formatter
- [ ] library/random/formatter/alphanumeric_spec.rb

### library/rbconfig
- [ ] library/rbconfig/rbconfig_spec.rb

### library/rbconfig/sizeof
- [ ] library/rbconfig/sizeof/limits_spec.rb
- [ ] library/rbconfig/sizeof/sizeof_spec.rb

### library/rbconfig
- [ ] library/rbconfig/unicode_emoji_version_spec.rb
- [ ] library/rbconfig/unicode_version_spec.rb

### library/readline
- [ ] library/readline/basic_quote_characters_spec.rb
- [ ] library/readline/basic_word_break_characters_spec.rb
- [ ] library/readline/completer_quote_characters_spec.rb
- [ ] library/readline/completer_word_break_characters_spec.rb
- [ ] library/readline/completion_append_character_spec.rb
- [ ] library/readline/completion_case_fold_spec.rb
- [ ] library/readline/completion_proc_spec.rb
- [ ] library/readline/constants_spec.rb
- [ ] library/readline/emacs_editing_mode_spec.rb
- [ ] library/readline/filename_quote_characters_spec.rb

### library/readline/history
- [ ] library/readline/history/append_spec.rb
- [ ] library/readline/history/delete_at_spec.rb
- [ ] library/readline/history/each_spec.rb
- [ ] library/readline/history/element_reference_spec.rb
- [ ] library/readline/history/element_set_spec.rb
- [ ] library/readline/history/empty_spec.rb
- [ ] library/readline/history/history_spec.rb
- [ ] library/readline/history/length_spec.rb
- [ ] library/readline/history/pop_spec.rb
- [ ] library/readline/history/push_spec.rb
- [ ] library/readline/history/shift_spec.rb
- [ ] library/readline/history/size_spec.rb
- [ ] library/readline/history/to_s_spec.rb

### library/readline
- [ ] library/readline/readline_spec.rb
- [ ] library/readline/vi_editing_mode_spec.rb

### library/resolv
- [ ] library/resolv/get_address_spec.rb
- [ ] library/resolv/get_addresses_spec.rb
- [ ] library/resolv/get_name_spec.rb
- [ ] library/resolv/get_names_spec.rb

### library/ripper
- [ ] library/ripper/lex_spec.rb
- [ ] library/ripper/sexp_spec.rb

### library/rubygems/gem
- [ ] library/rubygems/gem/bin_path_spec.rb
- [ ] library/rubygems/gem/load_path_insert_index_spec.rb

### library/securerandom
- [ ] library/securerandom/base64_spec.rb
- [ ] library/securerandom/bytes_spec.rb
- [ ] library/securerandom/hex_spec.rb
- [ ] library/securerandom/random_bytes_spec.rb
- [ ] library/securerandom/random_number_spec.rb

### library/shellwords
- [ ] library/shellwords/shellwords_spec.rb

### library/singleton
- [ ] library/singleton/allocate_spec.rb
- [ ] library/singleton/clone_spec.rb
- [ ] library/singleton/dump_spec.rb
- [ ] library/singleton/dup_spec.rb
- [ ] library/singleton/instance_spec.rb
- [ ] library/singleton/load_spec.rb
- [ ] library/singleton/new_spec.rb

### library/socket/addrinfo
- [ ] library/socket/addrinfo/afamily_spec.rb
- [ ] library/socket/addrinfo/bind_spec.rb
- [ ] library/socket/addrinfo/canonname_spec.rb
- [ ] library/socket/addrinfo/connect_from_spec.rb
- [ ] library/socket/addrinfo/connect_spec.rb
- [ ] library/socket/addrinfo/connect_to_spec.rb
- [ ] library/socket/addrinfo/family_addrinfo_spec.rb
- [ ] library/socket/addrinfo/foreach_spec.rb
- [ ] library/socket/addrinfo/getaddrinfo_spec.rb
- [ ] library/socket/addrinfo/getnameinfo_spec.rb
- [ ] library/socket/addrinfo/initialize_spec.rb
- [ ] library/socket/addrinfo/inspect_sockaddr_spec.rb
- [ ] library/socket/addrinfo/inspect_spec.rb
- [ ] library/socket/addrinfo/ip_address_spec.rb
- [ ] library/socket/addrinfo/ip_port_spec.rb
- [ ] library/socket/addrinfo/ip_spec.rb
- [ ] library/socket/addrinfo/ip_unpack_spec.rb
- [ ] library/socket/addrinfo/ipv4_loopback_spec.rb
- [ ] library/socket/addrinfo/ipv4_multicast_spec.rb
- [ ] library/socket/addrinfo/ipv4_private_spec.rb
- [ ] library/socket/addrinfo/ipv4_spec.rb
- [ ] library/socket/addrinfo/ipv6_linklocal_spec.rb
- [ ] library/socket/addrinfo/ipv6_loopback_spec.rb
- [ ] library/socket/addrinfo/ipv6_mc_global_spec.rb
- [ ] library/socket/addrinfo/ipv6_mc_linklocal_spec.rb
- [ ] library/socket/addrinfo/ipv6_mc_nodelocal_spec.rb
- [ ] library/socket/addrinfo/ipv6_mc_orglocal_spec.rb
- [ ] library/socket/addrinfo/ipv6_mc_sitelocal_spec.rb
- [ ] library/socket/addrinfo/ipv6_multicast_spec.rb
- [ ] library/socket/addrinfo/ipv6_sitelocal_spec.rb
- [ ] library/socket/addrinfo/ipv6_spec.rb
- [ ] library/socket/addrinfo/ipv6_to_ipv4_spec.rb
- [ ] library/socket/addrinfo/ipv6_unique_local_spec.rb
- [ ] library/socket/addrinfo/ipv6_unspecified_spec.rb
- [ ] library/socket/addrinfo/ipv6_v4compat_spec.rb
- [ ] library/socket/addrinfo/ipv6_v4mapped_spec.rb
- [ ] library/socket/addrinfo/listen_spec.rb
- [ ] library/socket/addrinfo/marshal_dump_spec.rb
- [ ] library/socket/addrinfo/marshal_load_spec.rb
- [ ] library/socket/addrinfo/pfamily_spec.rb
- [ ] library/socket/addrinfo/protocol_spec.rb
- [ ] library/socket/addrinfo/socktype_spec.rb
- [ ] library/socket/addrinfo/tcp_spec.rb
- [ ] library/socket/addrinfo/to_s_spec.rb
- [ ] library/socket/addrinfo/to_sockaddr_spec.rb
- [ ] library/socket/addrinfo/udp_spec.rb
- [ ] library/socket/addrinfo/unix_path_spec.rb
- [ ] library/socket/addrinfo/unix_spec.rb

### library/socket/ancillarydata
- [ ] library/socket/ancillarydata/cmsg_is_spec.rb
- [ ] library/socket/ancillarydata/data_spec.rb
- [ ] library/socket/ancillarydata/family_spec.rb
- [ ] library/socket/ancillarydata/initialize_spec.rb
- [ ] library/socket/ancillarydata/int_spec.rb
- [ ] library/socket/ancillarydata/ip_pktinfo_spec.rb
- [ ] library/socket/ancillarydata/ipv6_pktinfo_addr_spec.rb
- [ ] library/socket/ancillarydata/ipv6_pktinfo_ifindex_spec.rb
- [ ] library/socket/ancillarydata/ipv6_pktinfo_spec.rb
- [ ] library/socket/ancillarydata/level_spec.rb
- [ ] library/socket/ancillarydata/type_spec.rb
- [ ] library/socket/ancillarydata/unix_rights_spec.rb

### library/socket/basicsocket
- [ ] library/socket/basicsocket/close_read_spec.rb
- [ ] library/socket/basicsocket/close_write_spec.rb
- [ ] library/socket/basicsocket/connect_address_spec.rb
- [ ] library/socket/basicsocket/do_not_reverse_lookup_spec.rb
- [ ] library/socket/basicsocket/for_fd_spec.rb
- [ ] library/socket/basicsocket/getpeereid_spec.rb
- [ ] library/socket/basicsocket/getpeername_spec.rb
- [ ] library/socket/basicsocket/getsockname_spec.rb
- [ ] library/socket/basicsocket/getsockopt_spec.rb
- [ ] library/socket/basicsocket/ioctl_spec.rb
- [ ] library/socket/basicsocket/local_address_spec.rb
- [ ] library/socket/basicsocket/read_nonblock_spec.rb
- [ ] library/socket/basicsocket/read_spec.rb
- [ ] library/socket/basicsocket/recv_nonblock_spec.rb
- [ ] library/socket/basicsocket/recv_spec.rb
- [ ] library/socket/basicsocket/recvmsg_nonblock_spec.rb
- [ ] library/socket/basicsocket/recvmsg_spec.rb
- [ ] library/socket/basicsocket/remote_address_spec.rb
- [ ] library/socket/basicsocket/send_spec.rb
- [ ] library/socket/basicsocket/sendmsg_nonblock_spec.rb
- [ ] library/socket/basicsocket/sendmsg_spec.rb
- [ ] library/socket/basicsocket/setsockopt_spec.rb
- [ ] library/socket/basicsocket/shutdown_spec.rb
- [ ] library/socket/basicsocket/write_nonblock_spec.rb

### library/socket/constants
- [ ] library/socket/constants/constants_spec.rb

### library/socket/ipsocket
- [ ] library/socket/ipsocket/addr_spec.rb
- [ ] library/socket/ipsocket/getaddress_spec.rb
- [ ] library/socket/ipsocket/peeraddr_spec.rb
- [ ] library/socket/ipsocket/recvfrom_spec.rb

### library/socket/option
- [ ] library/socket/option/bool_spec.rb
- [ ] library/socket/option/initialize_spec.rb
- [ ] library/socket/option/inspect_spec.rb
- [ ] library/socket/option/int_spec.rb
- [ ] library/socket/option/linger_spec.rb
- [ ] library/socket/option/new_spec.rb

### library/socket/socket
- [ ] library/socket/socket/accept_loop_spec.rb
- [ ] library/socket/socket/accept_nonblock_spec.rb
- [ ] library/socket/socket/accept_spec.rb
- [ ] library/socket/socket/bind_spec.rb
- [ ] library/socket/socket/connect_nonblock_spec.rb
- [ ] library/socket/socket/connect_spec.rb
- [ ] library/socket/socket/for_fd_spec.rb
- [ ] library/socket/socket/getaddrinfo_spec.rb
- [ ] library/socket/socket/gethostbyaddr_spec.rb
- [ ] library/socket/socket/gethostbyname_spec.rb
- [ ] library/socket/socket/gethostname_spec.rb
- [ ] library/socket/socket/getifaddrs_spec.rb
- [ ] library/socket/socket/getnameinfo_spec.rb
- [ ] library/socket/socket/getservbyname_spec.rb
- [ ] library/socket/socket/getservbyport_spec.rb
- [ ] library/socket/socket/initialize_spec.rb
- [ ] library/socket/socket/ip_address_list_spec.rb
- [ ] library/socket/socket/ipv6only_bang_spec.rb
- [ ] library/socket/socket/listen_spec.rb
- [ ] library/socket/socket/local_address_spec.rb
- [ ] library/socket/socket/pack_sockaddr_in_spec.rb
- [ ] library/socket/socket/pack_sockaddr_un_spec.rb
- [ ] library/socket/socket/pair_spec.rb
- [ ] library/socket/socket/recvfrom_nonblock_spec.rb
- [ ] library/socket/socket/recvfrom_spec.rb
- [ ] library/socket/socket/remote_address_spec.rb
- [ ] library/socket/socket/sockaddr_in_spec.rb
- [ ] library/socket/socket/sockaddr_un_spec.rb
- [ ] library/socket/socket/socket_spec.rb
- [ ] library/socket/socket/socketpair_spec.rb
- [ ] library/socket/socket/sysaccept_spec.rb
- [ ] library/socket/socket/tcp_server_loop_spec.rb
- [ ] library/socket/socket/tcp_server_sockets_spec.rb
- [ ] library/socket/socket/tcp_spec.rb
- [ ] library/socket/socket/udp_server_loop_on_spec.rb
- [ ] library/socket/socket/udp_server_loop_spec.rb
- [ ] library/socket/socket/udp_server_recv_spec.rb
- [ ] library/socket/socket/udp_server_sockets_spec.rb
- [ ] library/socket/socket/unix_server_loop_spec.rb
- [ ] library/socket/socket/unix_server_socket_spec.rb
- [ ] library/socket/socket/unix_spec.rb
- [ ] library/socket/socket/unpack_sockaddr_in_spec.rb
- [ ] library/socket/socket/unpack_sockaddr_un_spec.rb

### library/socket/tcpserver
- [ ] library/socket/tcpserver/accept_nonblock_spec.rb
- [ ] library/socket/tcpserver/accept_spec.rb
- [ ] library/socket/tcpserver/gets_spec.rb
- [ ] library/socket/tcpserver/initialize_spec.rb
- [ ] library/socket/tcpserver/listen_spec.rb
- [ ] library/socket/tcpserver/new_spec.rb
- [ ] library/socket/tcpserver/sysaccept_spec.rb

### library/socket/tcpsocket
- [ ] library/socket/tcpsocket/gethostbyname_spec.rb
- [ ] library/socket/tcpsocket/initialize_spec.rb
- [ ] library/socket/tcpsocket/local_address_spec.rb
- [ ] library/socket/tcpsocket/open_spec.rb
- [ ] library/socket/tcpsocket/partially_closable_spec.rb
- [ ] library/socket/tcpsocket/recv_nonblock_spec.rb
- [ ] library/socket/tcpsocket/recv_spec.rb
- [ ] library/socket/tcpsocket/remote_address_spec.rb
- [ ] library/socket/tcpsocket/setsockopt_spec.rb

### library/socket/udpsocket
- [ ] library/socket/udpsocket/bind_spec.rb
- [ ] library/socket/udpsocket/connect_spec.rb
- [ ] library/socket/udpsocket/initialize_spec.rb
- [ ] library/socket/udpsocket/inspect_spec.rb
- [ ] library/socket/udpsocket/local_address_spec.rb
- [ ] library/socket/udpsocket/new_spec.rb
- [ ] library/socket/udpsocket/open_spec.rb
- [ ] library/socket/udpsocket/recvfrom_nonblock_spec.rb
- [ ] library/socket/udpsocket/remote_address_spec.rb
- [ ] library/socket/udpsocket/send_spec.rb
- [ ] library/socket/udpsocket/write_spec.rb

### library/socket/unixserver
- [ ] library/socket/unixserver/accept_nonblock_spec.rb
- [ ] library/socket/unixserver/accept_spec.rb
- [ ] library/socket/unixserver/for_fd_spec.rb
- [ ] library/socket/unixserver/initialize_spec.rb
- [ ] library/socket/unixserver/listen_spec.rb
- [ ] library/socket/unixserver/new_spec.rb
- [ ] library/socket/unixserver/open_spec.rb
- [ ] library/socket/unixserver/sysaccept_spec.rb

### library/socket/unixsocket
- [ ] library/socket/unixsocket/addr_spec.rb
- [ ] library/socket/unixsocket/initialize_spec.rb
- [ ] library/socket/unixsocket/inspect_spec.rb
- [ ] library/socket/unixsocket/local_address_spec.rb
- [ ] library/socket/unixsocket/new_spec.rb
- [ ] library/socket/unixsocket/open_spec.rb
- [ ] library/socket/unixsocket/pair_spec.rb
- [ ] library/socket/unixsocket/partially_closable_spec.rb
- [ ] library/socket/unixsocket/path_spec.rb
- [ ] library/socket/unixsocket/peeraddr_spec.rb
- [ ] library/socket/unixsocket/recv_io_spec.rb
- [ ] library/socket/unixsocket/recvfrom_spec.rb
- [ ] library/socket/unixsocket/remote_address_spec.rb
- [ ] library/socket/unixsocket/send_io_spec.rb
- [ ] library/socket/unixsocket/socketpair_spec.rb

### library/stringio
- [ ] library/stringio/append_spec.rb
- [ ] library/stringio/binmode_spec.rb
- [ ] library/stringio/close_read_spec.rb
- [ ] library/stringio/close_spec.rb
- [ ] library/stringio/close_write_spec.rb
- [ ] library/stringio/closed_read_spec.rb
- [ ] library/stringio/closed_spec.rb
- [ ] library/stringio/closed_write_spec.rb
- [ ] library/stringio/each_byte_spec.rb
- [ ] library/stringio/each_char_spec.rb
- [ ] library/stringio/each_codepoint_spec.rb
- [ ] library/stringio/each_line_spec.rb
- [ ] library/stringio/each_spec.rb
- [ ] library/stringio/eof_spec.rb
- [ ] library/stringio/external_encoding_spec.rb
- [ ] library/stringio/fcntl_spec.rb
- [ ] library/stringio/fileno_spec.rb
- [ ] library/stringio/flush_spec.rb
- [ ] library/stringio/fsync_spec.rb
- [ ] library/stringio/getbyte_spec.rb
- [ ] library/stringio/getc_spec.rb
- [ ] library/stringio/getch_spec.rb
- [ ] library/stringio/getpass_spec.rb
- [ ] library/stringio/gets_spec.rb
- [ ] library/stringio/initialize_spec.rb
- [ ] library/stringio/inspect_spec.rb
- [ ] library/stringio/internal_encoding_spec.rb
- [ ] library/stringio/isatty_spec.rb
- [ ] library/stringio/length_spec.rb
- [ ] library/stringio/lineno_spec.rb
- [ ] library/stringio/new_spec.rb
- [ ] library/stringio/open_spec.rb
- [ ] library/stringio/path_spec.rb
- [ ] library/stringio/pid_spec.rb
- [ ] library/stringio/pos_spec.rb
- [ ] library/stringio/print_spec.rb
- [ ] library/stringio/printf_spec.rb
- [ ] library/stringio/putc_spec.rb
- [ ] library/stringio/puts_spec.rb
- [ ] library/stringio/read_nonblock_spec.rb
- [ ] library/stringio/read_spec.rb
- [ ] library/stringio/readbyte_spec.rb
- [ ] library/stringio/readchar_spec.rb
- [ ] library/stringio/readline_spec.rb
- [ ] library/stringio/readlines_spec.rb
- [ ] library/stringio/readpartial_spec.rb
- [ ] library/stringio/reopen_spec.rb
- [ ] library/stringio/rewind_spec.rb
- [ ] library/stringio/seek_spec.rb
- [ ] library/stringio/set_encoding_by_bom_spec.rb
- [ ] library/stringio/set_encoding_spec.rb
- [ ] library/stringio/size_spec.rb
- [ ] library/stringio/string_spec.rb
- [ ] library/stringio/stringio_spec.rb
- [ ] library/stringio/sync_spec.rb
- [ ] library/stringio/sysread_spec.rb
- [ ] library/stringio/syswrite_spec.rb
- [ ] library/stringio/tell_spec.rb
- [ ] library/stringio/truncate_spec.rb
- [ ] library/stringio/tty_spec.rb
- [ ] library/stringio/ungetbyte_spec.rb
- [ ] library/stringio/ungetc_spec.rb
- [ ] library/stringio/write_nonblock_spec.rb
- [ ] library/stringio/write_spec.rb

### library/stringscanner
- [ ] library/stringscanner/append_spec.rb
- [ ] library/stringscanner/beginning_of_line_spec.rb
- [ ] library/stringscanner/bol_spec.rb
- [ ] library/stringscanner/captures_spec.rb
- [ ] library/stringscanner/charpos_spec.rb
- [ ] library/stringscanner/check_spec.rb
- [ ] library/stringscanner/check_until_spec.rb
- [ ] library/stringscanner/concat_spec.rb
- [ ] library/stringscanner/dup_spec.rb
- [ ] library/stringscanner/element_reference_spec.rb
- [ ] library/stringscanner/eos_spec.rb
- [ ] library/stringscanner/exist_spec.rb
- [ ] library/stringscanner/fixed_anchor_spec.rb
- [ ] library/stringscanner/get_byte_spec.rb
- [ ] library/stringscanner/getch_spec.rb
- [ ] library/stringscanner/initialize_spec.rb
- [ ] library/stringscanner/inspect_spec.rb
- [ ] library/stringscanner/match_spec.rb
- [ ] library/stringscanner/matched_size_spec.rb
- [ ] library/stringscanner/matched_spec.rb
- [ ] library/stringscanner/must_C_version_spec.rb
- [ ] library/stringscanner/named_captures_spec.rb
- [ ] library/stringscanner/peek_byte_spec.rb
- [ ] library/stringscanner/peek_spec.rb
- [ ] library/stringscanner/pointer_spec.rb
- [ ] library/stringscanner/pos_spec.rb
- [ ] library/stringscanner/post_match_spec.rb
- [ ] library/stringscanner/pre_match_spec.rb
- [ ] library/stringscanner/reset_spec.rb
- [ ] library/stringscanner/rest_size_spec.rb
- [ ] library/stringscanner/rest_spec.rb
- [ ] library/stringscanner/scan_byte_spec.rb
- [ ] library/stringscanner/scan_full_spec.rb
- [ ] library/stringscanner/scan_integer_spec.rb
- [ ] library/stringscanner/scan_spec.rb
- [ ] library/stringscanner/scan_until_spec.rb
- [ ] library/stringscanner/search_full_spec.rb
- [ ] library/stringscanner/size_spec.rb
- [ ] library/stringscanner/skip_spec.rb
- [ ] library/stringscanner/skip_until_spec.rb
- [ ] library/stringscanner/string_spec.rb
- [ ] library/stringscanner/terminate_spec.rb
- [ ] library/stringscanner/unscan_spec.rb
- [ ] library/stringscanner/values_at_spec.rb

### library/syslog
- [ ] library/syslog/alert_spec.rb
- [ ] library/syslog/close_spec.rb
- [ ] library/syslog/constants_spec.rb
- [ ] library/syslog/crit_spec.rb
- [ ] library/syslog/debug_spec.rb
- [ ] library/syslog/emerg_spec.rb
- [ ] library/syslog/err_spec.rb
- [ ] library/syslog/facility_spec.rb
- [ ] library/syslog/ident_spec.rb
- [ ] library/syslog/info_spec.rb
- [ ] library/syslog/inspect_spec.rb
- [ ] library/syslog/instance_spec.rb
- [ ] library/syslog/log_spec.rb
- [ ] library/syslog/mask_spec.rb
- [ ] library/syslog/notice_spec.rb
- [ ] library/syslog/open_spec.rb
- [ ] library/syslog/opened_spec.rb
- [ ] library/syslog/options_spec.rb
- [ ] library/syslog/reopen_spec.rb
- [ ] library/syslog/warning_spec.rb

### library/tempfile
- [ ] library/tempfile/_close_spec.rb
- [ ] library/tempfile/close_spec.rb
- [ ] library/tempfile/create_spec.rb
- [ ] library/tempfile/delete_spec.rb
- [ ] library/tempfile/initialize_spec.rb
- [ ] library/tempfile/length_spec.rb
- [ ] library/tempfile/open_spec.rb
- [ ] library/tempfile/path_spec.rb
- [ ] library/tempfile/size_spec.rb
- [ ] library/tempfile/unlink_spec.rb

### library/thread
- [ ] library/thread/queue_spec.rb
- [ ] library/thread/sizedqueue_spec.rb

### library/time
- [ ] library/time/httpdate_spec.rb
- [ ] library/time/iso8601_spec.rb
- [ ] library/time/rfc2822_spec.rb
- [ ] library/time/rfc822_spec.rb
- [ ] library/time/to_time_spec.rb
- [ ] library/time/xmlschema_spec.rb

### library/timeout
- [ ] library/timeout/error_spec.rb
- [ ] library/timeout/timeout_spec.rb

### library/tmpdir/dir
- [ ] library/tmpdir/dir/mktmpdir_spec.rb
- [ ] library/tmpdir/dir/tmpdir_spec.rb

### library/uri
- [ ] library/uri/decode_www_form_component_spec.rb
- [ ] library/uri/decode_www_form_spec.rb
- [ ] library/uri/encode_www_form_component_spec.rb
- [ ] library/uri/encode_www_form_spec.rb
- [ ] library/uri/eql_spec.rb
- [ ] library/uri/equality_spec.rb

### library/uri/escape
- [ ] library/uri/escape/decode_spec.rb
- [ ] library/uri/escape/encode_spec.rb
- [ ] library/uri/escape/escape_spec.rb
- [ ] library/uri/escape/unescape_spec.rb

### library/uri
- [ ] library/uri/extract_spec.rb

### library/uri/ftp
- [ ] library/uri/ftp/build_spec.rb
- [ ] library/uri/ftp/merge_spec.rb
- [ ] library/uri/ftp/new2_spec.rb
- [ ] library/uri/ftp/path_spec.rb
- [ ] library/uri/ftp/set_typecode_spec.rb
- [ ] library/uri/ftp/to_s_spec.rb
- [ ] library/uri/ftp/typecode_spec.rb

### library/uri/generic
- [ ] library/uri/generic/absolute_spec.rb
- [ ] library/uri/generic/build2_spec.rb
- [ ] library/uri/generic/build_spec.rb
- [ ] library/uri/generic/coerce_spec.rb
- [ ] library/uri/generic/component_ary_spec.rb
- [ ] library/uri/generic/component_spec.rb
- [ ] library/uri/generic/default_port_spec.rb
- [ ] library/uri/generic/eql_spec.rb
- [ ] library/uri/generic/equal_value_spec.rb
- [ ] library/uri/generic/fragment_spec.rb
- [ ] library/uri/generic/hash_spec.rb
- [ ] library/uri/generic/hierarchical_spec.rb
- [ ] library/uri/generic/host_spec.rb
- [ ] library/uri/generic/inspect_spec.rb
- [ ] library/uri/generic/merge_spec.rb
- [ ] library/uri/generic/minus_spec.rb
- [ ] library/uri/generic/normalize_spec.rb
- [ ] library/uri/generic/opaque_spec.rb
- [ ] library/uri/generic/password_spec.rb
- [ ] library/uri/generic/path_spec.rb
- [ ] library/uri/generic/plus_spec.rb
- [ ] library/uri/generic/port_spec.rb
- [ ] library/uri/generic/query_spec.rb
- [ ] library/uri/generic/registry_spec.rb
- [ ] library/uri/generic/relative_spec.rb
- [ ] library/uri/generic/route_from_spec.rb
- [ ] library/uri/generic/route_to_spec.rb
- [ ] library/uri/generic/scheme_spec.rb
- [ ] library/uri/generic/select_spec.rb
- [ ] library/uri/generic/set_fragment_spec.rb
- [ ] library/uri/generic/set_host_spec.rb
- [ ] library/uri/generic/set_opaque_spec.rb
- [ ] library/uri/generic/set_password_spec.rb
- [ ] library/uri/generic/set_path_spec.rb
- [ ] library/uri/generic/set_port_spec.rb
- [ ] library/uri/generic/set_query_spec.rb
- [ ] library/uri/generic/set_registry_spec.rb
- [ ] library/uri/generic/set_scheme_spec.rb
- [ ] library/uri/generic/set_user_spec.rb
- [ ] library/uri/generic/set_userinfo_spec.rb
- [ ] library/uri/generic/to_s_spec.rb
- [ ] library/uri/generic/use_registry_spec.rb
- [ ] library/uri/generic/user_spec.rb
- [ ] library/uri/generic/userinfo_spec.rb

### library/uri/http
- [ ] library/uri/http/build_spec.rb
- [ ] library/uri/http/request_uri_spec.rb

### library/uri
- [ ] library/uri/join_spec.rb

### library/uri/ldap
- [ ] library/uri/ldap/attributes_spec.rb
- [ ] library/uri/ldap/build_spec.rb
- [ ] library/uri/ldap/dn_spec.rb
- [ ] library/uri/ldap/extensions_spec.rb
- [ ] library/uri/ldap/filter_spec.rb
- [ ] library/uri/ldap/hierarchical_spec.rb
- [ ] library/uri/ldap/scope_spec.rb
- [ ] library/uri/ldap/set_attributes_spec.rb
- [ ] library/uri/ldap/set_dn_spec.rb
- [ ] library/uri/ldap/set_extensions_spec.rb
- [ ] library/uri/ldap/set_filter_spec.rb
- [ ] library/uri/ldap/set_scope_spec.rb

### library/uri/mailto
- [ ] library/uri/mailto/build_spec.rb
- [ ] library/uri/mailto/headers_spec.rb
- [ ] library/uri/mailto/set_headers_spec.rb
- [ ] library/uri/mailto/set_to_spec.rb
- [ ] library/uri/mailto/to_mailtext_spec.rb
- [ ] library/uri/mailto/to_rfc822text_spec.rb
- [ ] library/uri/mailto/to_s_spec.rb
- [ ] library/uri/mailto/to_spec.rb

### library/uri
- [ ] library/uri/merge_spec.rb
- [ ] library/uri/normalize_spec.rb
- [ ] library/uri/parse_spec.rb

### library/uri/parser
- [ ] library/uri/parser/escape_spec.rb
- [ ] library/uri/parser/extract_spec.rb
- [ ] library/uri/parser/inspect_spec.rb
- [ ] library/uri/parser/join_spec.rb
- [ ] library/uri/parser/make_regexp_spec.rb
- [ ] library/uri/parser/parse_spec.rb
- [ ] library/uri/parser/split_spec.rb
- [ ] library/uri/parser/unescape_spec.rb

### library/uri
- [ ] library/uri/plus_spec.rb
- [ ] library/uri/regexp_spec.rb
- [ ] library/uri/route_from_spec.rb
- [ ] library/uri/route_to_spec.rb
- [ ] library/uri/select_spec.rb
- [ ] library/uri/set_component_spec.rb
- [ ] library/uri/split_spec.rb
- [ ] library/uri/uri_spec.rb

### library/uri/util
- [ ] library/uri/util/make_components_hash_spec.rb

### library/weakref
- [ ] library/weakref/__getobj___spec.rb
- [ ] library/weakref/allocate_spec.rb
- [ ] library/weakref/new_spec.rb
- [ ] library/weakref/send_spec.rb
- [ ] library/weakref/weakref_alive_spec.rb

### library/win32ole/win32ole
- [ ] library/win32ole/win32ole/_getproperty_spec.rb
- [ ] library/win32ole/win32ole/_invoke_spec.rb
- [ ] library/win32ole/win32ole/codepage_spec.rb
- [ ] library/win32ole/win32ole/connect_spec.rb
- [ ] library/win32ole/win32ole/const_load_spec.rb
- [ ] library/win32ole/win32ole/constants_spec.rb
- [ ] library/win32ole/win32ole/create_guid_spec.rb
- [ ] library/win32ole/win32ole/invoke_spec.rb
- [ ] library/win32ole/win32ole/locale_spec.rb
- [ ] library/win32ole/win32ole/new_spec.rb
- [ ] library/win32ole/win32ole/ole_func_methods_spec.rb
- [ ] library/win32ole/win32ole/ole_get_methods_spec.rb
- [ ] library/win32ole/win32ole/ole_method_help_spec.rb
- [ ] library/win32ole/win32ole/ole_method_spec.rb
- [ ] library/win32ole/win32ole/ole_methods_spec.rb
- [ ] library/win32ole/win32ole/ole_obj_help_spec.rb
- [ ] library/win32ole/win32ole/ole_put_methods_spec.rb
- [ ] library/win32ole/win32ole/setproperty_spec.rb

### library/win32ole/win32ole_event
- [ ] library/win32ole/win32ole_event/new_spec.rb
- [ ] library/win32ole/win32ole_event/on_event_spec.rb

### library/win32ole/win32ole_method
- [ ] library/win32ole/win32ole_method/dispid_spec.rb
- [ ] library/win32ole/win32ole_method/event_interface_spec.rb
- [ ] library/win32ole/win32ole_method/event_spec.rb
- [ ] library/win32ole/win32ole_method/helpcontext_spec.rb
- [ ] library/win32ole/win32ole_method/helpfile_spec.rb
- [ ] library/win32ole/win32ole_method/helpstring_spec.rb
- [ ] library/win32ole/win32ole_method/invkind_spec.rb
- [ ] library/win32ole/win32ole_method/invoke_kind_spec.rb
- [ ] library/win32ole/win32ole_method/name_spec.rb
- [ ] library/win32ole/win32ole_method/new_spec.rb
- [ ] library/win32ole/win32ole_method/offset_vtbl_spec.rb
- [ ] library/win32ole/win32ole_method/params_spec.rb
- [ ] library/win32ole/win32ole_method/return_type_detail_spec.rb
- [ ] library/win32ole/win32ole_method/return_type_spec.rb
- [ ] library/win32ole/win32ole_method/return_vtype_spec.rb
- [ ] library/win32ole/win32ole_method/size_opt_params_spec.rb
- [ ] library/win32ole/win32ole_method/size_params_spec.rb
- [ ] library/win32ole/win32ole_method/to_s_spec.rb
- [ ] library/win32ole/win32ole_method/visible_spec.rb

### library/win32ole/win32ole_param
- [ ] library/win32ole/win32ole_param/default_spec.rb
- [ ] library/win32ole/win32ole_param/input_spec.rb
- [ ] library/win32ole/win32ole_param/name_spec.rb
- [ ] library/win32ole/win32ole_param/ole_type_detail_spec.rb
- [ ] library/win32ole/win32ole_param/ole_type_spec.rb
- [ ] library/win32ole/win32ole_param/optional_spec.rb
- [ ] library/win32ole/win32ole_param/retval_spec.rb
- [ ] library/win32ole/win32ole_param/to_s_spec.rb

### library/win32ole/win32ole_type
- [ ] library/win32ole/win32ole_type/guid_spec.rb
- [ ] library/win32ole/win32ole_type/helpcontext_spec.rb
- [ ] library/win32ole/win32ole_type/helpfile_spec.rb
- [ ] library/win32ole/win32ole_type/helpstring_spec.rb
- [ ] library/win32ole/win32ole_type/major_version_spec.rb
- [ ] library/win32ole/win32ole_type/minor_version_spec.rb
- [ ] library/win32ole/win32ole_type/name_spec.rb
- [ ] library/win32ole/win32ole_type/new_spec.rb
- [ ] library/win32ole/win32ole_type/ole_classes_spec.rb
- [ ] library/win32ole/win32ole_type/ole_methods_spec.rb
- [ ] library/win32ole/win32ole_type/ole_type_spec.rb
- [ ] library/win32ole/win32ole_type/progid_spec.rb
- [ ] library/win32ole/win32ole_type/progids_spec.rb
- [ ] library/win32ole/win32ole_type/src_type_spec.rb
- [ ] library/win32ole/win32ole_type/to_s_spec.rb
- [ ] library/win32ole/win32ole_type/typekind_spec.rb
- [ ] library/win32ole/win32ole_type/typelibs_spec.rb
- [ ] library/win32ole/win32ole_type/variables_spec.rb
- [ ] library/win32ole/win32ole_type/visible_spec.rb

### library/win32ole/win32ole_variable
- [ ] library/win32ole/win32ole_variable/name_spec.rb
- [ ] library/win32ole/win32ole_variable/ole_type_detail_spec.rb
- [ ] library/win32ole/win32ole_variable/ole_type_spec.rb
- [ ] library/win32ole/win32ole_variable/to_s_spec.rb
- [ ] library/win32ole/win32ole_variable/value_spec.rb
- [ ] library/win32ole/win32ole_variable/variable_kind_spec.rb
- [ ] library/win32ole/win32ole_variable/varkind_spec.rb
- [ ] library/win32ole/win32ole_variable/visible_spec.rb

### library/yaml
- [ ] library/yaml/dump_spec.rb
- [ ] library/yaml/dump_stream_spec.rb
- [ ] library/yaml/load_file_spec.rb
- [ ] library/yaml/load_spec.rb
- [ ] library/yaml/load_stream_spec.rb
- [ ] library/yaml/parse_file_spec.rb
- [ ] library/yaml/parse_spec.rb
- [ ] library/yaml/to_yaml_spec.rb
- [ ] library/yaml/unsafe_load_spec.rb

### library/zlib
- [ ] library/zlib/adler32_spec.rb
- [ ] library/zlib/crc32_spec.rb
- [ ] library/zlib/crc_table_spec.rb

### library/zlib/deflate
- [ ] library/zlib/deflate/deflate_spec.rb
- [ ] library/zlib/deflate/params_spec.rb
- [ ] library/zlib/deflate/set_dictionary_spec.rb

### library/zlib
- [ ] library/zlib/deflate_spec.rb
- [ ] library/zlib/gunzip_spec.rb
- [ ] library/zlib/gzip_spec.rb

### library/zlib/gzipfile
- [ ] library/zlib/gzipfile/close_spec.rb
- [ ] library/zlib/gzipfile/closed_spec.rb
- [ ] library/zlib/gzipfile/comment_spec.rb
- [ ] library/zlib/gzipfile/orig_name_spec.rb

### library/zlib/gzipreader
- [ ] library/zlib/gzipreader/each_byte_spec.rb
- [ ] library/zlib/gzipreader/each_char_spec.rb
- [ ] library/zlib/gzipreader/each_line_spec.rb
- [ ] library/zlib/gzipreader/each_spec.rb
- [ ] library/zlib/gzipreader/eof_spec.rb
- [ ] library/zlib/gzipreader/getc_spec.rb
- [ ] library/zlib/gzipreader/gets_spec.rb
- [ ] library/zlib/gzipreader/mtime_spec.rb
- [ ] library/zlib/gzipreader/pos_spec.rb
- [ ] library/zlib/gzipreader/read_spec.rb
- [ ] library/zlib/gzipreader/readpartial_spec.rb
- [ ] library/zlib/gzipreader/rewind_spec.rb
- [ ] library/zlib/gzipreader/ungetbyte_spec.rb
- [ ] library/zlib/gzipreader/ungetc_spec.rb

### library/zlib/gzipwriter
- [ ] library/zlib/gzipwriter/append_spec.rb
- [ ] library/zlib/gzipwriter/mtime_spec.rb
- [ ] library/zlib/gzipwriter/write_spec.rb

### library/zlib/inflate
- [ ] library/zlib/inflate/append_spec.rb
- [ ] library/zlib/inflate/finish_spec.rb
- [ ] library/zlib/inflate/inflate_spec.rb
- [ ] library/zlib/inflate/set_dictionary_spec.rb

### library/zlib
- [ ] library/zlib/inflate_spec.rb
- [ ] library/zlib/zlib_version_spec.rb

### library/zlib/zstream
- [ ] library/zlib/zstream/adler_spec.rb
- [ ] library/zlib/zstream/avail_in_spec.rb
- [ ] library/zlib/zstream/avail_out_spec.rb
- [ ] library/zlib/zstream/data_type_spec.rb
- [ ] library/zlib/zstream/flush_next_out_spec.rb

### optional/capi
- [ ] optional/capi/array_spec.rb
- [ ] optional/capi/basic_object_spec.rb
- [ ] optional/capi/bignum_spec.rb
- [ ] optional/capi/binding_spec.rb
- [ ] optional/capi/boolean_spec.rb
- [ ] optional/capi/class_spec.rb
- [ ] optional/capi/complex_spec.rb
- [ ] optional/capi/constants_spec.rb
- [ ] optional/capi/data_spec.rb
- [ ] optional/capi/debug_spec.rb
- [ ] optional/capi/digest_spec.rb
- [ ] optional/capi/encoding_spec.rb
- [ ] optional/capi/enumerator_spec.rb
- [ ] optional/capi/exception_spec.rb
- [ ] optional/capi/fiber_spec.rb
- [ ] optional/capi/file_spec.rb
- [ ] optional/capi/finalizer_spec.rb
- [ ] optional/capi/fixnum_spec.rb
- [ ] optional/capi/float_spec.rb
- [ ] optional/capi/gc_spec.rb
- [ ] optional/capi/globals_spec.rb
- [ ] optional/capi/hash_spec.rb
- [ ] optional/capi/integer_spec.rb
- [ ] optional/capi/io_spec.rb
- [ ] optional/capi/kernel_spec.rb
- [ ] optional/capi/language_spec.rb
- [ ] optional/capi/marshal_spec.rb
- [ ] optional/capi/module_spec.rb
- [ ] optional/capi/mutex_spec.rb
- [ ] optional/capi/numeric_spec.rb
- [ ] optional/capi/object_spec.rb
- [ ] optional/capi/proc_spec.rb
- [ ] optional/capi/range_spec.rb
- [ ] optional/capi/rational_spec.rb
- [ ] optional/capi/rbasic_spec.rb
- [ ] optional/capi/regexp_spec.rb
- [ ] optional/capi/set_spec.rb
- [ ] optional/capi/st_spec.rb
- [ ] optional/capi/string_spec.rb
- [ ] optional/capi/struct_spec.rb
- [ ] optional/capi/symbol_spec.rb
- [ ] optional/capi/thread_spec.rb
- [ ] optional/capi/time_spec.rb
- [ ] optional/capi/tracepoint_spec.rb
- [ ] optional/capi/typed_data_spec.rb
- [ ] optional/capi/util_spec.rb

### optional/thread_safety
- [ ] optional/thread_safety/hash_spec.rb

### security
- [ ] security/cve_2010_1330_spec.rb
- [ ] security/cve_2011_4815_spec.rb
- [ ] security/cve_2013_4164_spec.rb
- [ ] security/cve_2018_16396_spec.rb
- [ ] security/cve_2018_6914_spec.rb
- [ ] security/cve_2018_8778_spec.rb
- [ ] security/cve_2018_8779_spec.rb
- [ ] security/cve_2018_8780_spec.rb
- [ ] security/cve_2019_8321_spec.rb
- [ ] security/cve_2019_8322_spec.rb
- [ ] security/cve_2019_8323_spec.rb
- [ ] security/cve_2019_8325_spec.rb
- [ ] security/cve_2020_10663_spec.rb
- [ ] security/cve_2024_49761_spec.rb
