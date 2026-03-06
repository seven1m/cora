# Ruby Spec Porting TODO

Source baseline: ../ruby_spec compared to local spec/

[ ] Missing spec
[-] Partial-passing spec (not byte-for-byte matching upstream spec)
[x] Fully-passing spec

## Specs
### command_line
- [ ] backtrace_limit_spec.rb
- [ ] dash_0_spec.rb
- [ ] dash_a_spec.rb
- [ ] dash_c_spec.rb
- [ ] dash_d_spec.rb
- [ ] dash_e_spec.rb
- [ ] dash_encoding_spec.rb
- [ ] dash_external_encoding_spec.rb
- [ ] dash_internal_encoding_spec.rb
- [ ] dash_l_spec.rb
- [ ] dash_n_spec.rb
- [ ] dash_p_spec.rb
- [ ] dash_r_spec.rb
- [ ] dash_s_spec.rb
- [ ] dash_upper_c_spec.rb
- [ ] dash_upper_e_spec.rb
- [ ] dash_upper_f_spec.rb
- [ ] dash_upper_i_spec.rb
- [ ] dash_upper_k_spec.rb
- [ ] dash_upper_s_spec.rb
- [ ] dash_upper_u_spec.rb
- [ ] dash_upper_w_spec.rb
- [ ] dash_upper_x_spec.rb
- [ ] dash_v_spec.rb
- [ ] dash_w_spec.rb
- [ ] dash_x_spec.rb
- [ ] error_message_spec.rb
- [ ] feature_spec.rb
- [ ] frozen_strings_spec.rb
- [ ] rubylib_spec.rb
- [ ] rubyopt_spec.rb
- [ ] syntax_error_spec.rb

### core/argf
- [ ] argf_spec.rb
- [ ] argv_spec.rb
- [ ] binmode_spec.rb
- [ ] close_spec.rb
- [ ] closed_spec.rb
- [ ] each_byte_spec.rb
- [ ] each_char_spec.rb
- [ ] each_codepoint_spec.rb
- [ ] each_line_spec.rb
- [ ] each_spec.rb
- [ ] eof_spec.rb
- [ ] file_spec.rb
- [ ] filename_spec.rb
- [ ] fileno_spec.rb
- [ ] getc_spec.rb
- [ ] gets_spec.rb
- [ ] lineno_spec.rb
- [ ] path_spec.rb
- [ ] pos_spec.rb
- [ ] read_nonblock_spec.rb
- [ ] read_spec.rb
- [ ] readchar_spec.rb
- [ ] readline_spec.rb
- [ ] readlines_spec.rb
- [ ] readpartial_spec.rb
- [ ] rewind_spec.rb
- [ ] seek_spec.rb
- [ ] set_encoding_spec.rb
- [ ] skip_spec.rb
- [ ] tell_spec.rb
- [ ] to_a_spec.rb
- [ ] to_i_spec.rb
- [ ] to_io_spec.rb
- [ ] to_s_spec.rb

### core/array
- [ ] all_spec.rb
- [ ] allocate_spec.rb
- [ ] any_spec.rb
- [ ] append_spec.rb
- [ ] array_spec.rb
- [ ] assoc_spec.rb
- [ ] at_spec.rb
- [ ] bsearch_index_spec.rb
- [ ] bsearch_spec.rb
- [ ] clear_spec.rb
- [ ] clone_spec.rb
- [ ] collect_spec.rb
- [ ] combination_spec.rb
- [ ] compact_spec.rb
- [ ] comparison_spec.rb
- [ ] concat_spec.rb
- [ ] constructor_spec.rb
- [ ] count_spec.rb
- [ ] cycle_spec.rb
- [ ] deconstruct_spec.rb
- [ ] delete_at_spec.rb
- [ ] delete_if_spec.rb
- [ ] delete_spec.rb
- [ ] difference_spec.rb
- [ ] dig_spec.rb
- [ ] drop_spec.rb
- [ ] drop_while_spec.rb
- [ ] dup_spec.rb
- [ ] each_index_spec.rb
- [ ] each_spec.rb
- [ ] element_reference_spec.rb
- [ ] element_set_spec.rb
- [-] empty_spec.rb
- [ ] eql_spec.rb
- [ ] equal_value_spec.rb
- [ ] fetch_spec.rb
- [ ] fetch_values_spec.rb
- [ ] fill_spec.rb
- [ ] filter_spec.rb
- [ ] find_index_spec.rb
- [ ] first_spec.rb
- [ ] flatten_spec.rb
- [ ] frozen_spec.rb
- [ ] hash_spec.rb
- [ ] include_spec.rb
- [ ] index_spec.rb
- [ ] initialize_spec.rb
- [ ] insert_spec.rb
- [ ] inspect_spec.rb
- [ ] intersect_spec.rb
- [ ] intersection_spec.rb
- [ ] join_spec.rb
- [ ] keep_if_spec.rb
- [ ] last_spec.rb
- [x] length_spec.rb
- [ ] map_spec.rb
- [ ] max_spec.rb
- [ ] min_spec.rb
- [ ] minmax_spec.rb
- [ ] minus_spec.rb
- [ ] multiply_spec.rb
- [ ] new_spec.rb
- [ ] none_spec.rb
- [ ] one_spec.rb

### core/array/pack
- [ ] a_spec.rb
- [ ] at_spec.rb
- [ ] b_spec.rb
- [ ] buffer_spec.rb
- [ ] c_spec.rb
- [ ] comment_spec.rb
- [ ] d_spec.rb
- [ ] e_spec.rb
- [ ] empty_spec.rb
- [ ] f_spec.rb
- [ ] g_spec.rb
- [ ] h_spec.rb
- [ ] i_spec.rb
- [ ] j_spec.rb
- [ ] l_spec.rb
- [ ] m_spec.rb
- [ ] n_spec.rb
- [ ] p_spec.rb
- [ ] percent_spec.rb
- [ ] q_spec.rb
- [ ] s_spec.rb
- [ ] u_spec.rb
- [ ] v_spec.rb
- [ ] w_spec.rb
- [ ] x_spec.rb
- [ ] z_spec.rb

### core/array
- [ ] partition_spec.rb
- [ ] permutation_spec.rb
- [ ] plus_spec.rb
- [ ] pop_spec.rb
- [ ] prepend_spec.rb
- [ ] product_spec.rb
- [ ] push_spec.rb
- [ ] rassoc_spec.rb
- [ ] reject_spec.rb
- [ ] repeated_combination_spec.rb
- [ ] repeated_permutation_spec.rb
- [ ] replace_spec.rb
- [ ] reverse_each_spec.rb
- [ ] reverse_spec.rb
- [ ] rindex_spec.rb
- [ ] rotate_spec.rb
- [ ] sample_spec.rb
- [ ] select_spec.rb
- [ ] shift_spec.rb
- [ ] shuffle_spec.rb
- [ ] size_spec.rb
- [ ] slice_spec.rb
- [ ] sort_by_spec.rb
- [ ] sort_spec.rb
- [ ] sum_spec.rb
- [ ] take_spec.rb
- [ ] take_while_spec.rb
- [x] to_a_spec.rb
- [ ] to_ary_spec.rb
- [ ] to_h_spec.rb
- [ ] to_s_spec.rb
- [ ] transpose_spec.rb
- [ ] try_convert_spec.rb
- [ ] union_spec.rb
- [ ] uniq_spec.rb
- [ ] unshift_spec.rb
- [ ] values_at_spec.rb
- [ ] zip_spec.rb

### core/basicobject
- [ ] __id__spec.rb
- [ ] __send___spec.rb
- [ ] basicobject_spec.rb
- [ ] equal_spec.rb
- [ ] equal_value_spec.rb
- [ ] initialize_spec.rb
- [ ] instance_eval_spec.rb
- [ ] instance_exec_spec.rb
- [ ] method_missing_spec.rb
- [ ] not_equal_spec.rb
- [ ] not_spec.rb
- [ ] singleton_method_added_spec.rb
- [ ] singleton_method_removed_spec.rb
- [ ] singleton_method_undefined_spec.rb

### core/binding
- [ ] clone_spec.rb
- [ ] dup_spec.rb
- [ ] eval_spec.rb
- [ ] local_variable_defined_spec.rb
- [ ] local_variable_get_spec.rb
- [ ] local_variable_set_spec.rb
- [ ] local_variables_spec.rb
- [ ] receiver_spec.rb
- [ ] source_location_spec.rb

### core/builtin_constants
- [ ] builtin_constants_spec.rb

### core/class
- [ ] allocate_spec.rb
- [ ] attached_object_spec.rb
- [ ] dup_spec.rb
- [ ] inherited_spec.rb
- [ ] initialize_spec.rb
- [ ] new_spec.rb
- [ ] subclasses_spec.rb
- [ ] superclass_spec.rb

### core/comparable
- [ ] between_spec.rb
- [ ] clamp_spec.rb
- [ ] equal_value_spec.rb
- [ ] gt_spec.rb
- [ ] gte_spec.rb
- [ ] lt_spec.rb
- [ ] lte_spec.rb

### core/complex
- [ ] abs2_spec.rb
- [ ] abs_spec.rb
- [ ] angle_spec.rb
- [ ] arg_spec.rb
- [ ] coerce_spec.rb
- [ ] comparison_spec.rb
- [ ] conj_spec.rb
- [ ] conjugate_spec.rb
- [ ] constants_spec.rb
- [ ] denominator_spec.rb
- [ ] divide_spec.rb
- [ ] eql_spec.rb
- [ ] equal_value_spec.rb
- [ ] exponent_spec.rb
- [ ] fdiv_spec.rb
- [ ] finite_spec.rb
- [ ] hash_spec.rb
- [ ] imag_spec.rb
- [ ] imaginary_spec.rb
- [ ] infinite_spec.rb
- [ ] inspect_spec.rb
- [ ] integer_spec.rb
- [ ] magnitude_spec.rb
- [ ] marshal_dump_spec.rb
- [ ] minus_spec.rb
- [ ] multiply_spec.rb
- [ ] negative_spec.rb
- [ ] numerator_spec.rb
- [ ] phase_spec.rb
- [ ] plus_spec.rb
- [ ] polar_spec.rb
- [ ] positive_spec.rb
- [ ] quo_spec.rb
- [ ] rationalize_spec.rb
- [ ] real_spec.rb
- [ ] rect_spec.rb
- [ ] rectangular_spec.rb
- [ ] to_c_spec.rb
- [ ] to_f_spec.rb
- [ ] to_i_spec.rb
- [ ] to_r_spec.rb
- [ ] to_s_spec.rb
- [ ] uminus_spec.rb

### core/conditionvariable
- [ ] broadcast_spec.rb
- [ ] marshal_dump_spec.rb
- [ ] signal_spec.rb
- [ ] wait_spec.rb

### core/data
- [ ] constants_spec.rb
- [ ] deconstruct_keys_spec.rb
- [ ] deconstruct_spec.rb
- [ ] define_spec.rb
- [ ] eql_spec.rb
- [ ] equal_value_spec.rb
- [ ] hash_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb
- [ ] members_spec.rb
- [ ] to_h_spec.rb
- [ ] to_s_spec.rb
- [ ] with_spec.rb

### core/dir
- [ ] chdir_spec.rb
- [ ] children_spec.rb
- [ ] chroot_spec.rb
- [ ] close_spec.rb
- [ ] delete_spec.rb
- [ ] dir_spec.rb
- [ ] each_child_spec.rb
- [ ] each_spec.rb
- [ ] element_reference_spec.rb
- [ ] empty_spec.rb
- [ ] entries_spec.rb
- [ ] exist_spec.rb
- [ ] fchdir_spec.rb
- [ ] fileno_spec.rb
- [ ] for_fd_spec.rb
- [ ] foreach_spec.rb
- [ ] getwd_spec.rb
- [ ] glob_spec.rb
- [ ] home_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb
- [ ] mkdir_spec.rb
- [ ] open_spec.rb
- [ ] path_spec.rb
- [ ] pos_spec.rb
- [ ] pwd_spec.rb
- [ ] read_spec.rb
- [ ] rewind_spec.rb
- [ ] rmdir_spec.rb
- [ ] seek_spec.rb
- [ ] tell_spec.rb
- [ ] to_path_spec.rb
- [ ] unlink_spec.rb

### core/encoding
- [ ] _dump_spec.rb
- [ ] _load_spec.rb
- [ ] aliases_spec.rb
- [ ] ascii_compatible_spec.rb
- [ ] compatible_spec.rb

### core/encoding/converter
- [ ] asciicompat_encoding_spec.rb
- [ ] constants_spec.rb
- [ ] convert_spec.rb
- [ ] convpath_spec.rb
- [ ] destination_encoding_spec.rb
- [ ] finish_spec.rb
- [ ] insert_output_spec.rb
- [ ] inspect_spec.rb
- [ ] last_error_spec.rb
- [ ] new_spec.rb
- [ ] primitive_convert_spec.rb
- [ ] primitive_errinfo_spec.rb
- [ ] putback_spec.rb
- [ ] replacement_spec.rb
- [ ] search_convpath_spec.rb
- [ ] source_encoding_spec.rb

### core/encoding
- [x] default_external_spec.rb
- [x] default_internal_spec.rb
- [ ] dummy_spec.rb
- [ ] find_spec.rb
- [ ] inspect_spec.rb

### core/encoding/invalid_byte_sequence_error
- [ ] destination_encoding_name_spec.rb
- [ ] destination_encoding_spec.rb
- [ ] error_bytes_spec.rb
- [ ] incomplete_input_spec.rb
- [ ] readagain_bytes_spec.rb
- [ ] source_encoding_name_spec.rb
- [ ] source_encoding_spec.rb

### core/encoding
- [ ] list_spec.rb
- [ ] locale_charmap_spec.rb
- [ ] name_list_spec.rb
- [ ] name_spec.rb
- [ ] names_spec.rb
- [ ] replicate_spec.rb
- [ ] to_s_spec.rb

### core/encoding/undefined_conversion_error
- [ ] destination_encoding_name_spec.rb
- [ ] destination_encoding_spec.rb
- [ ] error_char_spec.rb
- [ ] source_encoding_name_spec.rb
- [ ] source_encoding_spec.rb

### core/enumerable
- [ ] all_spec.rb
- [ ] any_spec.rb
- [ ] chain_spec.rb
- [ ] chunk_spec.rb
- [ ] chunk_while_spec.rb
- [ ] collect_concat_spec.rb
- [ ] collect_spec.rb
- [ ] compact_spec.rb
- [ ] count_spec.rb
- [ ] cycle_spec.rb
- [ ] detect_spec.rb
- [ ] drop_spec.rb
- [ ] drop_while_spec.rb
- [ ] each_cons_spec.rb
- [ ] each_entry_spec.rb
- [ ] each_slice_spec.rb
- [ ] each_with_index_spec.rb
- [ ] each_with_object_spec.rb
- [ ] entries_spec.rb
- [ ] filter_map_spec.rb
- [ ] filter_spec.rb
- [ ] find_all_spec.rb
- [ ] find_index_spec.rb
- [ ] find_spec.rb
- [ ] first_spec.rb
- [ ] flat_map_spec.rb
- [ ] grep_spec.rb
- [ ] grep_v_spec.rb
- [ ] group_by_spec.rb
- [ ] include_spec.rb
- [ ] inject_spec.rb
- [ ] lazy_spec.rb
- [ ] map_spec.rb
- [ ] max_by_spec.rb
- [ ] max_spec.rb
- [ ] member_spec.rb
- [ ] min_by_spec.rb
- [ ] min_spec.rb
- [ ] minmax_by_spec.rb
- [ ] minmax_spec.rb
- [ ] none_spec.rb
- [ ] one_spec.rb
- [ ] partition_spec.rb
- [ ] reduce_spec.rb
- [ ] reject_spec.rb
- [ ] reverse_each_spec.rb
- [ ] select_spec.rb
- [ ] slice_after_spec.rb
- [ ] slice_before_spec.rb
- [ ] slice_when_spec.rb
- [ ] sort_by_spec.rb
- [ ] sort_spec.rb
- [ ] sum_spec.rb
- [ ] take_spec.rb
- [ ] take_while_spec.rb
- [ ] tally_spec.rb
- [ ] to_a_spec.rb
- [ ] to_h_spec.rb
- [ ] to_set_spec.rb
- [ ] uniq_spec.rb
- [ ] zip_spec.rb

### core/enumerator/arithmetic_sequence
- [ ] begin_spec.rb
- [ ] each_spec.rb
- [ ] end_spec.rb
- [ ] eq_spec.rb
- [ ] exclude_end_spec.rb
- [ ] first_spec.rb
- [ ] hash_spec.rb
- [ ] inspect_spec.rb
- [ ] last_spec.rb
- [ ] new_spec.rb
- [ ] size_spec.rb
- [ ] step_spec.rb

### core/enumerator/chain
- [ ] each_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb
- [ ] rewind_spec.rb
- [ ] size_spec.rb

### core/enumerator
- [x] each_spec.rb
- [ ] each_with_index_spec.rb
- [ ] each_with_object_spec.rb
- [x] enum_for_spec.rb
- [ ] enumerator_spec.rb
- [ ] feed_spec.rb
- [ ] first_spec.rb

### core/enumerator/generator
- [ ] each_spec.rb
- [ ] initialize_spec.rb

### core/enumerator
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb

### core/enumerator/lazy
- [ ] chunk_spec.rb
- [ ] chunk_while_spec.rb
- [ ] collect_concat_spec.rb
- [ ] collect_spec.rb
- [ ] compact_spec.rb
- [ ] drop_spec.rb
- [ ] drop_while_spec.rb
- [ ] eager_spec.rb
- [ ] enum_for_spec.rb
- [ ] filter_map_spec.rb
- [ ] filter_spec.rb
- [ ] find_all_spec.rb
- [ ] flat_map_spec.rb
- [ ] force_spec.rb
- [ ] grep_spec.rb
- [ ] grep_v_spec.rb
- [ ] initialize_spec.rb
- [ ] lazy_spec.rb
- [ ] map_spec.rb
- [ ] reject_spec.rb
- [ ] select_spec.rb
- [ ] slice_after_spec.rb
- [ ] slice_before_spec.rb
- [ ] slice_when_spec.rb
- [ ] take_spec.rb
- [ ] take_while_spec.rb
- [ ] to_enum_spec.rb
- [ ] uniq_spec.rb
- [ ] with_index_spec.rb
- [ ] zip_spec.rb

### core/enumerator
- [ ] new_spec.rb
- [ ] next_spec.rb
- [x] next_values_spec.rb
- [ ] peek_spec.rb
- [x] peek_values_spec.rb
- [ ] plus_spec.rb
- [ ] produce_spec.rb

### core/enumerator/product
- [ ] each_spec.rb
- [ ] initialize_copy_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb
- [ ] rewind_spec.rb
- [ ] size_spec.rb

### core/enumerator
- [ ] product_spec.rb
- [ ] rewind_spec.rb
- [ ] size_spec.rb
- [x] to_enum_spec.rb
- [ ] with_index_spec.rb
- [ ] with_object_spec.rb

### core/enumerator/yielder
- [ ] append_spec.rb
- [ ] initialize_spec.rb
- [ ] to_proc_spec.rb
- [ ] yield_spec.rb

### core/env
- [ ] assoc_spec.rb
- [ ] clear_spec.rb
- [ ] clone_spec.rb
- [ ] delete_if_spec.rb
- [ ] delete_spec.rb
- [ ] dup_spec.rb
- [ ] each_key_spec.rb
- [ ] each_pair_spec.rb
- [ ] each_spec.rb
- [ ] each_value_spec.rb
- [ ] element_reference_spec.rb
- [ ] element_set_spec.rb
- [ ] empty_spec.rb
- [ ] except_spec.rb
- [ ] fetch_spec.rb
- [ ] filter_spec.rb
- [ ] has_key_spec.rb
- [ ] has_value_spec.rb
- [ ] include_spec.rb
- [ ] inspect_spec.rb
- [ ] invert_spec.rb
- [ ] keep_if_spec.rb
- [ ] key_spec.rb
- [ ] keys_spec.rb
- [ ] length_spec.rb
- [ ] member_spec.rb
- [ ] merge_spec.rb
- [ ] rassoc_spec.rb
- [ ] rehash_spec.rb
- [ ] reject_spec.rb
- [ ] replace_spec.rb
- [ ] select_spec.rb
- [ ] shift_spec.rb
- [ ] size_spec.rb
- [ ] slice_spec.rb
- [ ] store_spec.rb
- [ ] to_a_spec.rb
- [ ] to_h_spec.rb
- [ ] to_hash_spec.rb
- [ ] to_s_spec.rb
- [ ] update_spec.rb
- [ ] value_spec.rb
- [ ] values_at_spec.rb
- [ ] values_spec.rb

### core/exception
- [ ] backtrace_locations_spec.rb
- [ ] backtrace_spec.rb
- [ ] case_compare_spec.rb
- [ ] cause_spec.rb
- [ ] detailed_message_spec.rb
- [ ] dup_spec.rb
- [ ] equal_value_spec.rb
- [ ] errno_spec.rb
- [ ] exception_spec.rb
- [ ] exit_value_spec.rb
- [ ] frozen_error_spec.rb
- [ ] full_message_spec.rb
- [ ] hierarchy_spec.rb
- [ ] inspect_spec.rb
- [ ] interrupt_spec.rb
- [ ] io_error_spec.rb
- [ ] key_error_spec.rb
- [ ] load_error_spec.rb
- [ ] message_spec.rb
- [ ] name_error_spec.rb
- [ ] name_spec.rb
- [ ] new_spec.rb
- [ ] no_method_error_spec.rb
- [ ] reason_spec.rb
- [ ] receiver_spec.rb
- [ ] result_spec.rb
- [ ] set_backtrace_spec.rb
- [ ] signal_exception_spec.rb
- [ ] signm_spec.rb
- [ ] signo_spec.rb
- [ ] standard_error_spec.rb
- [ ] status_spec.rb
- [ ] success_spec.rb
- [ ] syntax_error_spec.rb
- [ ] system_call_error_spec.rb
- [ ] system_exit_spec.rb
- [ ] to_s_spec.rb
- [ ] top_level_spec.rb
- [ ] uncaught_throw_error_spec.rb

### core/false
- [ ] and_spec.rb
- [ ] case_compare_spec.rb
- [ ] dup_spec.rb
- [ ] falseclass_spec.rb
- [x] inspect_spec.rb
- [ ] or_spec.rb
- [ ] singleton_method_spec.rb
- [ ] to_s_spec.rb
- [ ] xor_spec.rb

### core/fiber
- [-] alive_spec.rb
- [ ] blocking_spec.rb
- [ ] current_spec.rb
- [ ] inspect_spec.rb
- [ ] kill_spec.rb
- [x] new_spec.rb
- [ ] raise_spec.rb
- [ ] resume_spec.rb
- [ ] scheduler_spec.rb
- [ ] set_scheduler_spec.rb
- [ ] storage_spec.rb
- [ ] transfer_spec.rb
- [x] yield_spec.rb

### core/file
- [ ] absolute_path_spec.rb
- [ ] atime_spec.rb
- [ ] basename_spec.rb
- [ ] birthtime_spec.rb
- [ ] blockdev_spec.rb
- [ ] chardev_spec.rb
- [ ] chmod_spec.rb
- [ ] chown_spec.rb

### core/file/constants
- [ ] constants_spec.rb

### core/file
- [ ] constants_spec.rb
- [ ] ctime_spec.rb
- [ ] delete_spec.rb
- [ ] directory_spec.rb
- [ ] dirname_spec.rb
- [ ] empty_spec.rb
- [ ] executable_real_spec.rb
- [ ] executable_spec.rb
- [ ] exist_spec.rb
- [ ] expand_path_spec.rb
- [ ] extname_spec.rb
- [ ] file_spec.rb
- [ ] flock_spec.rb
- [ ] fnmatch_spec.rb
- [ ] ftype_spec.rb
- [ ] grpowned_spec.rb
- [ ] identical_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb
- [ ] join_spec.rb
- [ ] lchmod_spec.rb
- [ ] lchown_spec.rb
- [ ] link_spec.rb
- [ ] lstat_spec.rb
- [ ] lutime_spec.rb
- [ ] mkfifo_spec.rb
- [ ] mtime_spec.rb
- [ ] new_spec.rb
- [ ] null_spec.rb
- [ ] open_spec.rb
- [ ] owned_spec.rb
- [ ] path_spec.rb
- [ ] pipe_spec.rb
- [ ] printf_spec.rb
- [ ] read_spec.rb
- [ ] readable_real_spec.rb
- [ ] readable_spec.rb
- [ ] readlink_spec.rb
- [ ] realdirpath_spec.rb
- [ ] realpath_spec.rb
- [ ] rename_spec.rb
- [ ] reopen_spec.rb
- [ ] setgid_spec.rb
- [ ] setuid_spec.rb
- [ ] size_spec.rb
- [ ] socket_spec.rb
- [ ] split_spec.rb

### core/file/stat
- [ ] atime_spec.rb
- [ ] birthtime_spec.rb
- [ ] blksize_spec.rb
- [ ] blockdev_spec.rb
- [ ] blocks_spec.rb
- [ ] chardev_spec.rb
- [ ] comparison_spec.rb
- [ ] ctime_spec.rb
- [ ] dev_major_spec.rb
- [ ] dev_minor_spec.rb
- [ ] dev_spec.rb
- [ ] directory_spec.rb
- [ ] executable_real_spec.rb
- [ ] executable_spec.rb
- [ ] file_spec.rb
- [ ] ftype_spec.rb
- [ ] gid_spec.rb
- [ ] grpowned_spec.rb
- [ ] ino_spec.rb
- [ ] inspect_spec.rb
- [ ] mode_spec.rb
- [ ] mtime_spec.rb
- [ ] new_spec.rb
- [ ] nlink_spec.rb
- [ ] owned_spec.rb
- [ ] pipe_spec.rb
- [ ] rdev_major_spec.rb
- [ ] rdev_minor_spec.rb
- [ ] rdev_spec.rb
- [ ] readable_real_spec.rb
- [ ] readable_spec.rb
- [ ] setgid_spec.rb
- [ ] setuid_spec.rb
- [ ] size_spec.rb
- [ ] socket_spec.rb
- [ ] sticky_spec.rb
- [ ] symlink_spec.rb
- [ ] uid_spec.rb
- [ ] world_readable_spec.rb
- [ ] world_writable_spec.rb
- [ ] writable_real_spec.rb
- [ ] writable_spec.rb
- [ ] zero_spec.rb

### core/file
- [ ] stat_spec.rb
- [ ] sticky_spec.rb
- [ ] symlink_spec.rb
- [ ] to_path_spec.rb
- [ ] truncate_spec.rb
- [ ] umask_spec.rb
- [ ] unlink_spec.rb
- [ ] utime_spec.rb
- [ ] world_readable_spec.rb
- [ ] world_writable_spec.rb
- [ ] writable_real_spec.rb
- [ ] writable_spec.rb
- [ ] zero_spec.rb

### core/filetest
- [ ] blockdev_spec.rb
- [ ] chardev_spec.rb
- [ ] directory_spec.rb
- [ ] executable_real_spec.rb
- [ ] executable_spec.rb
- [ ] exist_spec.rb
- [ ] file_spec.rb
- [ ] grpowned_spec.rb
- [ ] identical_spec.rb
- [ ] owned_spec.rb
- [ ] pipe_spec.rb
- [ ] readable_real_spec.rb
- [ ] readable_spec.rb
- [ ] setgid_spec.rb
- [ ] setuid_spec.rb
- [ ] size_spec.rb
- [ ] socket_spec.rb
- [ ] sticky_spec.rb
- [ ] symlink_spec.rb
- [ ] world_readable_spec.rb
- [ ] world_writable_spec.rb
- [ ] writable_real_spec.rb
- [ ] writable_spec.rb
- [ ] zero_spec.rb

### core/float
- [ ] abs_spec.rb
- [ ] angle_spec.rb
- [ ] arg_spec.rb
- [ ] case_compare_spec.rb
- [ ] ceil_spec.rb
- [ ] coerce_spec.rb
- [ ] comparison_spec.rb
- [ ] constants_spec.rb
- [ ] denominator_spec.rb
- [ ] divide_spec.rb
- [ ] divmod_spec.rb
- [ ] dup_spec.rb
- [ ] eql_spec.rb
- [ ] equal_value_spec.rb
- [ ] exponent_spec.rb
- [ ] fdiv_spec.rb
- [ ] finite_spec.rb
- [ ] float_spec.rb
- [ ] floor_spec.rb
- [ ] gt_spec.rb
- [ ] gte_spec.rb
- [ ] hash_spec.rb
- [ ] infinite_spec.rb
- [ ] inspect_spec.rb
- [ ] lt_spec.rb
- [ ] lte_spec.rb
- [ ] magnitude_spec.rb
- [ ] minus_spec.rb
- [ ] modulo_spec.rb
- [ ] multiply_spec.rb
- [ ] nan_spec.rb
- [ ] negative_spec.rb
- [ ] next_float_spec.rb
- [ ] numerator_spec.rb
- [ ] phase_spec.rb
- [ ] plus_spec.rb
- [ ] positive_spec.rb
- [ ] prev_float_spec.rb
- [ ] quo_spec.rb
- [ ] rationalize_spec.rb
- [ ] round_spec.rb
- [ ] to_f_spec.rb
- [ ] to_i_spec.rb
- [ ] to_int_spec.rb
- [ ] to_r_spec.rb
- [ ] to_s_spec.rb
- [ ] truncate_spec.rb
- [ ] uminus_spec.rb
- [ ] uplus_spec.rb
- [ ] zero_spec.rb

### core/gc
- [ ] auto_compact_spec.rb
- [ ] config_spec.rb
- [ ] count_spec.rb
- [ ] disable_spec.rb
- [ ] enable_spec.rb
- [ ] garbage_collect_spec.rb
- [ ] measure_total_time_spec.rb

### core/gc/profiler
- [ ] clear_spec.rb
- [ ] disable_spec.rb
- [ ] enable_spec.rb
- [ ] enabled_spec.rb
- [ ] report_spec.rb
- [ ] result_spec.rb
- [ ] total_time_spec.rb

### core/gc
- [ ] start_spec.rb
- [ ] stat_spec.rb
- [ ] stress_spec.rb
- [ ] total_time_spec.rb

### core/hash
- [ ] allocate_spec.rb
- [ ] any_spec.rb
- [ ] assoc_spec.rb
- [ ] clear_spec.rb
- [ ] clone_spec.rb
- [ ] compact_spec.rb
- [ ] compare_by_identity_spec.rb
- [ ] constructor_spec.rb
- [ ] deconstruct_keys_spec.rb
- [ ] default_proc_spec.rb
- [ ] default_spec.rb
- [ ] delete_if_spec.rb
- [ ] delete_spec.rb
- [ ] dig_spec.rb
- [ ] each_key_spec.rb
- [ ] each_pair_spec.rb
- [ ] each_spec.rb
- [ ] each_value_spec.rb
- [ ] element_reference_spec.rb
- [ ] element_set_spec.rb
- [ ] empty_spec.rb
- [ ] eql_spec.rb
- [ ] equal_value_spec.rb
- [ ] except_spec.rb
- [ ] fetch_spec.rb
- [ ] fetch_values_spec.rb
- [ ] filter_spec.rb
- [ ] flatten_spec.rb
- [ ] gt_spec.rb
- [ ] gte_spec.rb
- [ ] has_key_spec.rb
- [ ] has_value_spec.rb
- [ ] hash_spec.rb
- [ ] include_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb
- [ ] invert_spec.rb
- [ ] keep_if_spec.rb
- [ ] key_spec.rb
- [ ] keys_spec.rb
- [ ] length_spec.rb
- [ ] lt_spec.rb
- [ ] lte_spec.rb
- [ ] member_spec.rb
- [ ] merge_spec.rb
- [ ] new_spec.rb
- [ ] rassoc_spec.rb
- [ ] rehash_spec.rb
- [ ] reject_spec.rb
- [ ] replace_spec.rb
- [ ] ruby2_keywords_hash_spec.rb
- [ ] select_spec.rb
- [ ] shift_spec.rb
- [ ] size_spec.rb
- [ ] slice_spec.rb
- [ ] sort_spec.rb
- [ ] store_spec.rb
- [ ] to_a_spec.rb
- [ ] to_h_spec.rb
- [ ] to_hash_spec.rb
- [ ] to_proc_spec.rb
- [ ] to_s_spec.rb
- [ ] transform_keys_spec.rb
- [ ] transform_values_spec.rb
- [ ] try_convert_spec.rb
- [ ] update_spec.rb
- [ ] value_spec.rb
- [ ] values_at_spec.rb
- [ ] values_spec.rb

### core/integer
- [ ] abs_spec.rb
- [ ] allbits_spec.rb
- [ ] anybits_spec.rb
- [ ] bit_and_spec.rb
- [ ] bit_length_spec.rb
- [ ] bit_or_spec.rb
- [ ] bit_xor_spec.rb
- [ ] case_compare_spec.rb
- [ ] ceil_spec.rb
- [ ] ceildiv_spec.rb
- [ ] chr_spec.rb
- [ ] coerce_spec.rb
- [ ] comparison_spec.rb
- [ ] complement_spec.rb
- [ ] constants_spec.rb
- [ ] denominator_spec.rb
- [ ] digits_spec.rb
- [ ] div_spec.rb
- [ ] divide_spec.rb
- [ ] divmod_spec.rb
- [ ] downto_spec.rb
- [ ] dup_spec.rb
- [ ] element_reference_spec.rb
- [ ] equal_value_spec.rb
- [ ] even_spec.rb
- [ ] exponent_spec.rb
- [ ] fdiv_spec.rb
- [ ] floor_spec.rb
- [ ] gcd_spec.rb
- [ ] gcdlcm_spec.rb
- [ ] gt_spec.rb
- [ ] gte_spec.rb
- [ ] integer_spec.rb
- [ ] lcm_spec.rb
- [ ] left_shift_spec.rb
- [ ] lt_spec.rb
- [ ] lte_spec.rb
- [ ] magnitude_spec.rb
- [ ] minus_spec.rb
- [ ] modulo_spec.rb
- [ ] multiply_spec.rb
- [ ] next_spec.rb
- [ ] nobits_spec.rb
- [ ] numerator_spec.rb
- [ ] odd_spec.rb
- [ ] ord_spec.rb
- [ ] plus_spec.rb
- [ ] pow_spec.rb
- [ ] pred_spec.rb
- [ ] rationalize_spec.rb
- [ ] remainder_spec.rb
- [ ] right_shift_spec.rb
- [ ] round_spec.rb
- [ ] size_spec.rb
- [ ] sqrt_spec.rb
- [ ] succ_spec.rb
- [ ] times_spec.rb
- [ ] to_f_spec.rb
- [ ] to_i_spec.rb
- [ ] to_int_spec.rb
- [ ] to_r_spec.rb
- [ ] to_s_spec.rb
- [ ] truncate_spec.rb
- [ ] try_convert_spec.rb
- [ ] uminus_spec.rb
- [ ] upto_spec.rb
- [ ] zero_spec.rb

### core/io
- [ ] advise_spec.rb
- [ ] autoclose_spec.rb
- [ ] binmode_spec.rb
- [ ] binread_spec.rb
- [ ] binwrite_spec.rb

### core/io/buffer
- [ ] and_spec.rb
- [ ] empty_spec.rb
- [ ] external_spec.rb
- [ ] for_spec.rb
- [ ] free_spec.rb
- [ ] initialize_spec.rb
- [ ] internal_spec.rb
- [ ] locked_spec.rb
- [ ] map_spec.rb
- [ ] mapped_spec.rb
- [ ] not_spec.rb
- [ ] null_spec.rb
- [ ] or_spec.rb
- [ ] private_spec.rb
- [ ] readonly_spec.rb
- [ ] resize_spec.rb
- [ ] shared_spec.rb
- [ ] string_spec.rb
- [ ] transfer_spec.rb
- [ ] valid_spec.rb
- [ ] xor_spec.rb

### core/io
- [ ] close_on_exec_spec.rb
- [ ] close_read_spec.rb
- [ ] close_spec.rb
- [ ] close_write_spec.rb
- [ ] closed_spec.rb
- [ ] constants_spec.rb
- [ ] copy_stream_spec.rb
- [ ] dup_spec.rb
- [ ] each_byte_spec.rb
- [ ] each_char_spec.rb
- [ ] each_codepoint_spec.rb
- [ ] each_line_spec.rb
- [ ] each_spec.rb
- [ ] eof_spec.rb
- [ ] external_encoding_spec.rb
- [ ] fcntl_spec.rb
- [ ] fdatasync_spec.rb
- [ ] fileno_spec.rb
- [ ] flush_spec.rb
- [ ] for_fd_spec.rb
- [ ] foreach_spec.rb
- [ ] fsync_spec.rb
- [ ] getbyte_spec.rb
- [ ] getc_spec.rb
- [ ] gets_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb
- [ ] internal_encoding_spec.rb
- [ ] io_spec.rb
- [ ] ioctl_spec.rb
- [ ] isatty_spec.rb
- [ ] lineno_spec.rb
- [ ] new_spec.rb
- [ ] nonblock_spec.rb
- [ ] open_spec.rb
- [ ] output_spec.rb
- [ ] path_spec.rb
- [ ] pid_spec.rb
- [ ] pipe_spec.rb
- [ ] popen_spec.rb
- [ ] pos_spec.rb
- [ ] pread_spec.rb
- [ ] print_spec.rb
- [ ] printf_spec.rb
- [ ] putc_spec.rb
- [ ] puts_spec.rb
- [ ] pwrite_spec.rb
- [ ] read_nonblock_spec.rb
- [ ] read_spec.rb
- [ ] readbyte_spec.rb
- [ ] readchar_spec.rb
- [ ] readline_spec.rb
- [ ] readlines_spec.rb
- [ ] readpartial_spec.rb
- [ ] reopen_spec.rb
- [ ] rewind_spec.rb
- [ ] seek_spec.rb
- [ ] select_spec.rb
- [ ] set_encoding_by_bom_spec.rb
- [ ] set_encoding_spec.rb
- [ ] stat_spec.rb
- [ ] sync_spec.rb
- [ ] sysopen_spec.rb
- [ ] sysread_spec.rb
- [ ] sysseek_spec.rb
- [ ] syswrite_spec.rb
- [ ] tell_spec.rb
- [ ] to_i_spec.rb
- [ ] to_io_spec.rb
- [ ] try_convert_spec.rb
- [ ] tty_spec.rb
- [ ] ungetbyte_spec.rb
- [ ] ungetc_spec.rb
- [ ] write_nonblock_spec.rb
- [ ] write_spec.rb

### core/kernel
- [ ] Array_spec.rb
- [ ] Complex_spec.rb
- [ ] Float_spec.rb
- [ ] Hash_spec.rb
- [ ] Integer_spec.rb
- [ ] Rational_spec.rb
- [ ] String_spec.rb
- [ ] __callee___spec.rb
- [ ] __dir___spec.rb
- [ ] __method___spec.rb
- [ ] abort_spec.rb
- [ ] at_exit_spec.rb
- [ ] autoload_spec.rb
- [ ] backtick_spec.rb
- [ ] binding_spec.rb
- [ ] block_given_spec.rb
- [ ] caller_locations_spec.rb
- [ ] caller_spec.rb
- [ ] case_compare_spec.rb
- [ ] catch_spec.rb
- [ ] chomp_spec.rb
- [ ] chop_spec.rb
- [ ] class_spec.rb
- [ ] clone_spec.rb
- [ ] comparison_spec.rb
- [ ] define_singleton_method_spec.rb
- [ ] display_spec.rb
- [ ] dup_spec.rb
- [x] enum_for_spec.rb
- [ ] eql_spec.rb
- [ ] equal_value_spec.rb
- [ ] eval_spec.rb
- [ ] exec_spec.rb
- [ ] exit_spec.rb
- [ ] extend_spec.rb
- [ ] fail_spec.rb
- [ ] fork_spec.rb
- [ ] format_spec.rb
- [ ] freeze_spec.rb
- [ ] frozen_spec.rb
- [ ] gets_spec.rb
- [ ] global_variables_spec.rb
- [ ] gsub_spec.rb
- [ ] initialize_clone_spec.rb
- [ ] initialize_copy_spec.rb
- [ ] initialize_dup_spec.rb
- [ ] inspect_spec.rb
- [ ] instance_of_spec.rb
- [ ] instance_variable_defined_spec.rb
- [ ] instance_variable_get_spec.rb
- [ ] instance_variable_set_spec.rb
- [ ] instance_variables_spec.rb
- [ ] is_a_spec.rb
- [ ] itself_spec.rb
- [ ] kind_of_spec.rb
- [ ] lambda_spec.rb
- [ ] load_spec.rb
- [ ] local_variables_spec.rb
- [ ] loop_spec.rb
- [ ] match_spec.rb
- [ ] method_spec.rb
- [ ] methods_spec.rb
- [ ] nil_spec.rb
- [ ] not_match_spec.rb
- [ ] object_id_spec.rb
- [ ] open_spec.rb
- [ ] p_spec.rb
- [ ] pp_spec.rb
- [ ] print_spec.rb
- [ ] printf_spec.rb
- [ ] private_methods_spec.rb
- [ ] proc_spec.rb
- [ ] protected_methods_spec.rb
- [ ] public_method_spec.rb
- [ ] public_methods_spec.rb
- [ ] public_send_spec.rb
- [ ] putc_spec.rb
- [ ] puts_spec.rb
- [ ] raise_spec.rb
- [ ] rand_spec.rb
- [ ] readline_spec.rb
- [ ] readlines_spec.rb
- [ ] remove_instance_variable_spec.rb
- [ ] require_relative_spec.rb
- [ ] require_spec.rb
- [ ] respond_to_missing_spec.rb
- [ ] respond_to_spec.rb
- [ ] select_spec.rb
- [ ] send_spec.rb
- [ ] set_trace_func_spec.rb
- [ ] singleton_class_spec.rb
- [ ] singleton_method_spec.rb
- [ ] singleton_methods_spec.rb
- [ ] sleep_spec.rb
- [ ] spawn_spec.rb
- [ ] sprintf_spec.rb
- [ ] srand_spec.rb
- [ ] sub_spec.rb
- [ ] syscall_spec.rb
- [ ] system_spec.rb
- [ ] taint_spec.rb
- [ ] tainted_spec.rb
- [ ] tap_spec.rb
- [ ] test_spec.rb
- [ ] then_spec.rb
- [ ] throw_spec.rb
- [x] to_enum_spec.rb
- [ ] to_s_spec.rb
- [ ] trace_var_spec.rb
- [ ] trap_spec.rb
- [ ] trust_spec.rb
- [ ] untaint_spec.rb
- [ ] untrace_var_spec.rb
- [ ] untrust_spec.rb
- [ ] untrusted_spec.rb
- [ ] warn_spec.rb
- [ ] yield_self_spec.rb

### core/main
- [ ] define_method_spec.rb
- [ ] include_spec.rb
- [ ] private_spec.rb
- [ ] public_spec.rb
- [ ] ruby2_keywords_spec.rb
- [ ] to_s_spec.rb
- [ ] using_spec.rb

### core/marshal
- [ ] dump_spec.rb
- [ ] float_spec.rb
- [ ] load_spec.rb
- [ ] major_version_spec.rb
- [ ] minor_version_spec.rb
- [ ] restore_spec.rb

### core/matchdata
- [ ] allocate_spec.rb
- [ ] begin_spec.rb
- [ ] bytebegin_spec.rb
- [ ] byteend_spec.rb
- [ ] byteoffset_spec.rb
- [ ] captures_spec.rb
- [ ] deconstruct_keys_spec.rb
- [ ] deconstruct_spec.rb
- [ ] dup_spec.rb
- [ ] element_reference_spec.rb
- [ ] end_spec.rb
- [ ] eql_spec.rb
- [ ] equal_value_spec.rb
- [ ] hash_spec.rb
- [ ] inspect_spec.rb
- [ ] length_spec.rb
- [ ] match_length_spec.rb
- [ ] match_spec.rb
- [ ] named_captures_spec.rb
- [ ] names_spec.rb
- [ ] offset_spec.rb
- [ ] post_match_spec.rb
- [ ] pre_match_spec.rb
- [ ] regexp_spec.rb
- [ ] size_spec.rb
- [ ] string_spec.rb
- [ ] to_a_spec.rb
- [ ] to_s_spec.rb
- [ ] values_at_spec.rb

### core/math
- [ ] acos_spec.rb
- [ ] acosh_spec.rb
- [ ] asin_spec.rb
- [ ] asinh_spec.rb
- [ ] atan2_spec.rb
- [ ] atan_spec.rb
- [ ] atanh_spec.rb
- [ ] cbrt_spec.rb
- [ ] constants_spec.rb
- [ ] cos_spec.rb
- [ ] cosh_spec.rb
- [ ] erf_spec.rb
- [ ] erfc_spec.rb
- [ ] exp_spec.rb
- [ ] expm1_spec.rb
- [ ] frexp_spec.rb
- [ ] gamma_spec.rb
- [ ] hypot_spec.rb
- [ ] ldexp_spec.rb
- [ ] lgamma_spec.rb
- [ ] log10_spec.rb
- [ ] log1p_spec.rb
- [ ] log2_spec.rb
- [ ] log_spec.rb
- [ ] sin_spec.rb
- [ ] sinh_spec.rb
- [ ] sqrt_spec.rb
- [ ] tan_spec.rb
- [ ] tanh_spec.rb

### core/method
- [ ] arity_spec.rb
- [ ] call_spec.rb
- [ ] case_compare_spec.rb
- [ ] clone_spec.rb
- [ ] compose_spec.rb
- [ ] curry_spec.rb
- [ ] dup_spec.rb
- [ ] element_reference_spec.rb
- [ ] eql_spec.rb
- [ ] equal_value_spec.rb
- [ ] hash_spec.rb
- [ ] inspect_spec.rb
- [ ] name_spec.rb
- [ ] original_name_spec.rb
- [ ] owner_spec.rb
- [ ] parameters_spec.rb
- [ ] private_spec.rb
- [ ] protected_spec.rb
- [ ] public_spec.rb
- [ ] receiver_spec.rb
- [ ] source_location_spec.rb
- [ ] super_method_spec.rb
- [ ] to_proc_spec.rb
- [ ] to_s_spec.rb
- [ ] unbind_spec.rb

### core/module
- [ ] alias_method_spec.rb
- [ ] ancestors_spec.rb
- [ ] append_features_spec.rb
- [ ] attr_accessor_spec.rb
- [ ] attr_reader_spec.rb
- [ ] attr_spec.rb
- [ ] attr_writer_spec.rb
- [ ] autoload_spec.rb
- [ ] case_compare_spec.rb
- [ ] class_eval_spec.rb
- [ ] class_exec_spec.rb
- [ ] class_variable_defined_spec.rb
- [ ] class_variable_get_spec.rb
- [ ] class_variable_set_spec.rb
- [ ] class_variables_spec.rb
- [ ] comparison_spec.rb
- [ ] const_added_spec.rb
- [ ] const_defined_spec.rb
- [ ] const_get_spec.rb
- [ ] const_missing_spec.rb
- [ ] const_set_spec.rb
- [ ] const_source_location_spec.rb
- [ ] constants_spec.rb
- [ ] define_method_spec.rb
- [ ] define_singleton_method_spec.rb
- [ ] deprecate_constant_spec.rb
- [ ] eql_spec.rb
- [ ] equal_spec.rb
- [ ] equal_value_spec.rb
- [ ] extend_object_spec.rb
- [ ] extended_spec.rb
- [ ] freeze_spec.rb
- [ ] gt_spec.rb
- [ ] gte_spec.rb
- [ ] include_spec.rb
- [ ] included_modules_spec.rb
- [ ] included_spec.rb
- [ ] initialize_copy_spec.rb
- [ ] initialize_spec.rb
- [ ] instance_method_spec.rb
- [ ] instance_methods_spec.rb
- [ ] lt_spec.rb
- [ ] lte_spec.rb
- [ ] method_added_spec.rb
- [ ] method_defined_spec.rb
- [ ] method_removed_spec.rb
- [ ] method_undefined_spec.rb
- [ ] module_eval_spec.rb
- [ ] module_exec_spec.rb
- [ ] module_function_spec.rb
- [ ] name_spec.rb
- [ ] nesting_spec.rb
- [ ] new_spec.rb
- [ ] prepend_features_spec.rb
- [ ] prepend_spec.rb
- [ ] prepended_spec.rb
- [ ] private_class_method_spec.rb
- [ ] private_constant_spec.rb
- [ ] private_instance_methods_spec.rb
- [ ] private_method_defined_spec.rb
- [ ] private_spec.rb
- [ ] protected_instance_methods_spec.rb
- [ ] protected_method_defined_spec.rb
- [ ] protected_spec.rb
- [ ] public_class_method_spec.rb
- [ ] public_constant_spec.rb
- [ ] public_instance_method_spec.rb
- [ ] public_instance_methods_spec.rb
- [ ] public_method_defined_spec.rb
- [ ] public_spec.rb
- [ ] refine_spec.rb
- [ ] refinements_spec.rb
- [ ] remove_class_variable_spec.rb
- [ ] remove_const_spec.rb
- [ ] remove_method_spec.rb
- [ ] ruby2_keywords_spec.rb
- [ ] set_temporary_name_spec.rb
- [ ] singleton_class_spec.rb
- [ ] to_s_spec.rb
- [ ] undef_method_spec.rb
- [ ] undefined_instance_methods_spec.rb
- [ ] used_refinements_spec.rb
- [ ] using_spec.rb

### core/mutex
- [ ] lock_spec.rb
- [ ] locked_spec.rb
- [ ] owned_spec.rb
- [ ] sleep_spec.rb
- [ ] synchronize_spec.rb
- [ ] try_lock_spec.rb
- [ ] unlock_spec.rb

### core/nil
- [ ] and_spec.rb
- [ ] case_compare_spec.rb
- [ ] dup_spec.rb
- [ ] inspect_spec.rb
- [ ] match_spec.rb
- [ ] nil_spec.rb
- [ ] nilclass_spec.rb
- [ ] or_spec.rb
- [ ] rationalize_spec.rb
- [ ] singleton_method_spec.rb
- [ ] to_a_spec.rb
- [ ] to_c_spec.rb
- [ ] to_f_spec.rb
- [ ] to_h_spec.rb
- [ ] to_i_spec.rb
- [ ] to_r_spec.rb
- [ ] to_s_spec.rb
- [ ] xor_spec.rb

### core/numeric
- [ ] abs2_spec.rb
- [ ] abs_spec.rb
- [ ] angle_spec.rb
- [ ] arg_spec.rb
- [ ] ceil_spec.rb
- [ ] clone_spec.rb
- [ ] coerce_spec.rb
- [ ] comparison_spec.rb
- [ ] conj_spec.rb
- [ ] conjugate_spec.rb
- [ ] denominator_spec.rb
- [ ] div_spec.rb
- [ ] divmod_spec.rb
- [ ] dup_spec.rb
- [ ] eql_spec.rb
- [ ] fdiv_spec.rb
- [ ] finite_spec.rb
- [ ] floor_spec.rb
- [ ] i_spec.rb
- [ ] imag_spec.rb
- [ ] imaginary_spec.rb
- [ ] infinite_spec.rb
- [ ] integer_spec.rb
- [ ] magnitude_spec.rb
- [ ] modulo_spec.rb
- [ ] negative_spec.rb
- [ ] nonzero_spec.rb
- [ ] numerator_spec.rb
- [ ] numeric_spec.rb
- [ ] phase_spec.rb
- [ ] polar_spec.rb
- [ ] positive_spec.rb
- [ ] quo_spec.rb
- [ ] real_spec.rb
- [ ] rect_spec.rb
- [ ] rectangular_spec.rb
- [ ] remainder_spec.rb
- [ ] round_spec.rb
- [ ] singleton_method_added_spec.rb
- [ ] step_spec.rb
- [ ] to_c_spec.rb
- [ ] to_int_spec.rb
- [ ] truncate_spec.rb
- [ ] uminus_spec.rb
- [ ] uplus_spec.rb
- [ ] zero_spec.rb

### core/objectspace
- [ ] _id2ref_spec.rb
- [ ] count_objects_spec.rb
- [ ] define_finalizer_spec.rb
- [ ] each_object_spec.rb
- [ ] garbage_collect_spec.rb
- [ ] undefine_finalizer_spec.rb

### core/objectspace/weakkeymap
- [ ] clear_spec.rb
- [ ] delete_spec.rb
- [ ] element_reference_spec.rb
- [ ] element_set_spec.rb
- [ ] getkey_spec.rb
- [ ] inspect_spec.rb
- [ ] key_spec.rb

### core/objectspace/weakmap
- [ ] delete_spec.rb
- [ ] each_key_spec.rb
- [ ] each_pair_spec.rb
- [ ] each_spec.rb
- [ ] each_value_spec.rb
- [ ] element_reference_spec.rb
- [ ] element_set_spec.rb
- [ ] include_spec.rb
- [ ] inspect_spec.rb
- [ ] key_spec.rb
- [ ] keys_spec.rb
- [ ] length_spec.rb
- [ ] member_spec.rb
- [ ] size_spec.rb
- [ ] values_spec.rb

### core/objectspace
- [ ] weakmap_spec.rb

### core/proc
- [ ] allocate_spec.rb
- [ ] arity_spec.rb
- [ ] binding_spec.rb
- [ ] block_pass_spec.rb
- [ ] call_spec.rb
- [ ] case_compare_spec.rb
- [ ] clone_spec.rb
- [ ] compose_spec.rb
- [ ] curry_spec.rb
- [ ] dup_spec.rb
- [ ] element_reference_spec.rb
- [ ] eql_spec.rb
- [ ] equal_value_spec.rb
- [ ] hash_spec.rb
- [ ] inspect_spec.rb
- [ ] lambda_spec.rb
- [ ] new_spec.rb
- [ ] parameters_spec.rb
- [ ] ruby2_keywords_spec.rb
- [ ] source_location_spec.rb
- [ ] to_proc_spec.rb
- [ ] to_s_spec.rb
- [ ] yield_spec.rb

### core/process
- [ ] _fork_spec.rb
- [ ] abort_spec.rb
- [ ] argv0_spec.rb
- [ ] clock_getres_spec.rb
- [ ] clock_gettime_spec.rb
- [ ] constants_spec.rb
- [ ] daemon_spec.rb
- [ ] detach_spec.rb
- [ ] egid_spec.rb
- [ ] euid_spec.rb
- [ ] exec_spec.rb
- [ ] exit_spec.rb
- [ ] fork_spec.rb
- [ ] getpgid_spec.rb
- [ ] getpgrp_spec.rb
- [ ] getpriority_spec.rb
- [ ] getrlimit_spec.rb

### core/process/gid
- [ ] change_privilege_spec.rb
- [ ] eid_spec.rb
- [ ] grant_privilege_spec.rb
- [ ] re_exchange_spec.rb
- [ ] re_exchangeable_spec.rb
- [ ] rid_spec.rb
- [ ] sid_available_spec.rb
- [ ] switch_spec.rb

### core/process
- [ ] gid_spec.rb
- [ ] groups_spec.rb
- [ ] initgroups_spec.rb
- [ ] kill_spec.rb
- [ ] last_status_spec.rb
- [ ] maxgroups_spec.rb
- [ ] pid_spec.rb
- [ ] ppid_spec.rb
- [ ] set_proctitle_spec.rb
- [ ] setpgid_spec.rb
- [ ] setpgrp_spec.rb
- [ ] setpriority_spec.rb
- [ ] setrlimit_spec.rb
- [ ] setsid_spec.rb
- [ ] spawn_spec.rb

### core/process/status
- [ ] bit_and_spec.rb
- [ ] coredump_spec.rb
- [ ] equal_value_spec.rb
- [ ] exited_spec.rb
- [ ] exitstatus_spec.rb
- [ ] inspect_spec.rb
- [ ] pid_spec.rb
- [ ] right_shift_spec.rb
- [ ] signaled_spec.rb
- [ ] stopped_spec.rb
- [ ] stopsig_spec.rb
- [ ] success_spec.rb
- [ ] termsig_spec.rb
- [ ] to_i_spec.rb
- [ ] to_int_spec.rb
- [ ] to_s_spec.rb
- [ ] wait_spec.rb

### core/process/sys
- [ ] getegid_spec.rb
- [ ] geteuid_spec.rb
- [ ] getgid_spec.rb
- [ ] getuid_spec.rb
- [ ] issetugid_spec.rb
- [ ] setegid_spec.rb
- [ ] seteuid_spec.rb
- [ ] setgid_spec.rb
- [ ] setregid_spec.rb
- [ ] setresgid_spec.rb
- [ ] setresuid_spec.rb
- [ ] setreuid_spec.rb
- [ ] setrgid_spec.rb
- [ ] setruid_spec.rb
- [ ] setuid_spec.rb

### core/process
- [ ] times_spec.rb

### core/process/tms
- [ ] cstime_spec.rb
- [ ] cutime_spec.rb
- [ ] stime_spec.rb
- [ ] utime_spec.rb

### core/process/uid
- [ ] change_privilege_spec.rb
- [ ] eid_spec.rb
- [ ] grant_privilege_spec.rb
- [ ] re_exchange_spec.rb
- [ ] re_exchangeable_spec.rb
- [ ] rid_spec.rb
- [ ] sid_available_spec.rb
- [ ] switch_spec.rb

### core/process
- [ ] uid_spec.rb
- [ ] wait2_spec.rb
- [ ] wait_spec.rb
- [ ] waitall_spec.rb
- [ ] waitpid2_spec.rb
- [ ] waitpid_spec.rb
- [ ] warmup_spec.rb

### core/queue
- [ ] append_spec.rb
- [ ] clear_spec.rb
- [ ] close_spec.rb
- [ ] closed_spec.rb
- [ ] deq_spec.rb
- [ ] empty_spec.rb
- [ ] enq_spec.rb
- [ ] freeze_spec.rb
- [ ] initialize_spec.rb
- [ ] length_spec.rb
- [ ] num_waiting_spec.rb
- [ ] pop_spec.rb
- [ ] push_spec.rb
- [ ] shift_spec.rb
- [ ] size_spec.rb

### core/random
- [ ] bytes_spec.rb
- [ ] default_spec.rb
- [ ] equal_value_spec.rb
- [ ] new_seed_spec.rb
- [ ] new_spec.rb
- [ ] rand_spec.rb
- [ ] random_number_spec.rb
- [ ] seed_spec.rb
- [ ] srand_spec.rb
- [ ] urandom_spec.rb

### core/range
- [ ] begin_spec.rb
- [ ] bsearch_spec.rb
- [ ] case_compare_spec.rb
- [ ] clone_spec.rb
- [ ] count_spec.rb
- [ ] cover_spec.rb
- [ ] dup_spec.rb
- [ ] each_spec.rb
- [ ] end_spec.rb
- [ ] eql_spec.rb
- [ ] equal_value_spec.rb
- [ ] exclude_end_spec.rb
- [ ] first_spec.rb
- [ ] frozen_spec.rb
- [ ] hash_spec.rb
- [ ] include_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb
- [ ] last_spec.rb
- [ ] max_spec.rb
- [ ] member_spec.rb
- [ ] min_spec.rb
- [ ] minmax_spec.rb
- [ ] new_spec.rb
- [ ] overlap_spec.rb
- [ ] percent_spec.rb
- [ ] range_spec.rb
- [ ] reverse_each_spec.rb
- [ ] size_spec.rb
- [ ] step_spec.rb
- [ ] to_a_spec.rb
- [ ] to_s_spec.rb
- [ ] to_set_spec.rb

### core/rational
- [ ] abs_spec.rb
- [ ] ceil_spec.rb
- [ ] comparison_spec.rb
- [ ] denominator_spec.rb
- [ ] div_spec.rb
- [ ] divide_spec.rb
- [ ] divmod_spec.rb
- [ ] equal_value_spec.rb
- [ ] exponent_spec.rb
- [ ] fdiv_spec.rb
- [ ] floor_spec.rb
- [ ] hash_spec.rb
- [ ] inspect_spec.rb
- [ ] integer_spec.rb
- [ ] magnitude_spec.rb
- [ ] marshal_dump_spec.rb
- [ ] minus_spec.rb
- [ ] modulo_spec.rb
- [ ] multiply_spec.rb
- [ ] numerator_spec.rb
- [ ] plus_spec.rb
- [ ] quo_spec.rb
- [ ] rational_spec.rb
- [ ] rationalize_spec.rb
- [ ] remainder_spec.rb
- [ ] round_spec.rb
- [ ] to_f_spec.rb
- [ ] to_i_spec.rb
- [ ] to_r_spec.rb
- [ ] to_s_spec.rb
- [ ] truncate_spec.rb
- [ ] zero_spec.rb

### core/refinement
- [ ] append_features_spec.rb
- [ ] extend_object_spec.rb
- [ ] import_methods_spec.rb
- [ ] include_spec.rb
- [ ] prepend_features_spec.rb
- [ ] prepend_spec.rb
- [ ] refined_class_spec.rb
- [ ] target_spec.rb

### core/regexp
- [ ] case_compare_spec.rb
- [ ] casefold_spec.rb
- [ ] compile_spec.rb
- [ ] encoding_spec.rb
- [ ] eql_spec.rb
- [ ] equal_value_spec.rb
- [ ] escape_spec.rb
- [ ] fixed_encoding_spec.rb
- [ ] hash_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb
- [ ] last_match_spec.rb
- [ ] linear_time_spec.rb
- [ ] match_spec.rb
- [ ] named_captures_spec.rb
- [ ] names_spec.rb
- [ ] new_spec.rb
- [ ] options_spec.rb
- [ ] quote_spec.rb
- [ ] source_spec.rb
- [ ] timeout_spec.rb
- [ ] to_s_spec.rb
- [ ] try_convert_spec.rb
- [ ] union_spec.rb

### core/set
- [ ] add_spec.rb
- [ ] append_spec.rb
- [ ] case_compare_spec.rb
- [ ] case_equality_spec.rb
- [ ] classify_spec.rb
- [ ] clear_spec.rb
- [ ] collect_spec.rb
- [ ] compare_by_identity_spec.rb
- [ ] comparison_spec.rb
- [ ] constructor_spec.rb
- [ ] delete_if_spec.rb
- [ ] delete_spec.rb
- [ ] difference_spec.rb
- [ ] disjoint_spec.rb
- [ ] divide_spec.rb
- [ ] each_spec.rb
- [ ] empty_spec.rb

### core/set/enumerable
- [ ] to_set_spec.rb

### core/set
- [ ] eql_spec.rb
- [ ] equal_value_spec.rb
- [ ] exclusion_spec.rb
- [ ] filter_spec.rb
- [ ] flatten_merge_spec.rb
- [ ] flatten_spec.rb
- [ ] hash_spec.rb
- [ ] include_spec.rb
- [ ] initialize_clone_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb
- [ ] intersect_spec.rb
- [ ] intersection_spec.rb
- [ ] join_spec.rb
- [ ] keep_if_spec.rb
- [ ] length_spec.rb
- [ ] map_spec.rb
- [ ] member_spec.rb
- [ ] merge_spec.rb
- [ ] minus_spec.rb
- [ ] plus_spec.rb
- [ ] pretty_print_cycle_spec.rb
- [ ] proper_subset_spec.rb
- [ ] proper_superset_spec.rb
- [ ] reject_spec.rb
- [ ] replace_spec.rb
- [ ] select_spec.rb
- [ ] set_spec.rb
- [ ] size_spec.rb

### core/set/sortedset
- [ ] sortedset_spec.rb

### core/set
- [ ] subset_spec.rb
- [ ] subtract_spec.rb
- [ ] superset_spec.rb
- [ ] to_a_spec.rb
- [ ] to_s_spec.rb
- [ ] union_spec.rb

### core/signal
- [ ] list_spec.rb
- [ ] signame_spec.rb
- [ ] trap_spec.rb

### core/sizedqueue
- [ ] append_spec.rb
- [ ] clear_spec.rb
- [ ] close_spec.rb
- [ ] closed_spec.rb
- [ ] deq_spec.rb
- [ ] empty_spec.rb
- [ ] enq_spec.rb
- [ ] freeze_spec.rb
- [ ] length_spec.rb
- [ ] max_spec.rb
- [ ] new_spec.rb
- [ ] num_waiting_spec.rb
- [ ] pop_spec.rb
- [ ] push_spec.rb
- [ ] shift_spec.rb
- [ ] size_spec.rb

### core/string
- [x] allocate_spec.rb
- [x] append_as_bytes_spec.rb
- [x] append_spec.rb
- [x] ascii_only_spec.rb
- [x] b_spec.rb
- [ ] byteindex_spec.rb
- [ ] byterindex_spec.rb
- [x] bytes_spec.rb
- [x] bytesize_spec.rb
- [x] byteslice_spec.rb
- [ ] bytesplice_spec.rb
- [ ] capitalize_spec.rb
- [x] case_compare_spec.rb
- [ ] casecmp_spec.rb
- [ ] center_spec.rb
- [x] chars_spec.rb
- [ ] chilled_string_spec.rb
- [ ] chomp_spec.rb
- [ ] chop_spec.rb
- [x] chr_spec.rb
- [x] clear_spec.rb
- [x] clone_spec.rb
- [x] codepoints_spec.rb
- [x] comparison_spec.rb
- [x] concat_spec.rb
- [ ] count_spec.rb
- [ ] crypt_spec.rb
- [ ] dedup_spec.rb
- [x] delete_prefix_spec.rb
- [ ] delete_spec.rb
- [x] delete_suffix_spec.rb
- [x] downcase_spec.rb
- [ ] dump_spec.rb
- [x] dup_spec.rb
- [x] each_byte_spec.rb
- [x] each_char_spec.rb
- [x] each_codepoint_spec.rb
- [ ] each_grapheme_cluster_spec.rb
- [ ] each_line_spec.rb
- [ ] element_reference_spec.rb
- [x] element_set_spec.rb
- [x] empty_spec.rb
- [x] encode_spec.rb
- [x] encoding_spec.rb
- [x] end_with_spec.rb
- [x] eql_spec.rb
- [x] equal_value_spec.rb
- [x] force_encoding_spec.rb
- [x] freeze_spec.rb
- [x] getbyte_spec.rb
- [ ] grapheme_clusters_spec.rb
- [ ] gsub_spec.rb
- [x] hash_spec.rb
- [x] hex_spec.rb
- [x] include_spec.rb
- [ ] index_spec.rb
- [x] initialize_spec.rb
- [x] insert_spec.rb
- [x] inspect_spec.rb
- [x] intern_spec.rb
- [x] length_spec.rb
- [ ] lines_spec.rb
- [ ] ljust_spec.rb
- [ ] lstrip_spec.rb
- [ ] match_spec.rb
- [ ] modulo_spec.rb
- [x] multiply_spec.rb
- [x] new_spec.rb
- [ ] next_spec.rb
- [x] oct_spec.rb
- [x] ord_spec.rb
- [ ] partition_spec.rb
- [x] plus_spec.rb
- [x] prepend_spec.rb
- [x] replace_spec.rb
- [x] reverse_spec.rb
- [ ] rindex_spec.rb
- [ ] rjust_spec.rb
- [ ] rpartition_spec.rb
- [ ] rstrip_spec.rb
- [x] scan_spec.rb
- [ ] scrub_spec.rb
- [x] setbyte_spec.rb
- [x] size_spec.rb
- [ ] slice_spec.rb
- [ ] split_spec.rb
- [ ] squeeze_spec.rb
- [x] start_with_spec.rb
- [x] string_spec.rb
- [ ] strip_spec.rb
- [ ] sub_spec.rb
- [ ] succ_spec.rb
- [ ] sum_spec.rb
- [ ] swapcase_spec.rb
- [ ] to_c_spec.rb
- [ ] to_f_spec.rb
- [x] to_i_spec.rb
- [ ] to_r_spec.rb
- [x] to_s_spec.rb
- [x] to_str_spec.rb
- [x] to_sym_spec.rb
- [ ] tr_s_spec.rb
- [ ] tr_spec.rb
- [x] try_convert_spec.rb
- [ ] uminus_spec.rb
- [ ] undump_spec.rb
- [ ] unicode_normalize_spec.rb
- [ ] unicode_normalized_spec.rb

### core/string/unpack
- [ ] a_spec.rb
- [ ] at_spec.rb
- [x] b_spec.rb
- [ ] c_spec.rb
- [ ] comment_spec.rb
- [ ] d_spec.rb
- [ ] e_spec.rb
- [ ] f_spec.rb
- [ ] g_spec.rb
- [ ] h_spec.rb
- [ ] i_spec.rb
- [ ] j_spec.rb
- [ ] l_spec.rb
- [x] m_spec.rb
- [ ] n_spec.rb
- [ ] p_spec.rb
- [ ] percent_spec.rb
- [ ] q_spec.rb
- [ ] s_spec.rb
- [x] u_spec.rb
- [ ] v_spec.rb
- [ ] w_spec.rb
- [ ] x_spec.rb
- [ ] z_spec.rb

### core/string
- [x] unpack1_spec.rb
- [x] unpack_spec.rb
- [x] upcase_spec.rb
- [x] uplus_spec.rb
- [ ] upto_spec.rb

### core/string/valid_encoding
- [x] utf_8_spec.rb

### core/string
- [x] valid_encoding_spec.rb

### core/struct
- [ ] clone_spec.rb
- [ ] constants_spec.rb
- [ ] deconstruct_keys_spec.rb
- [ ] deconstruct_spec.rb
- [ ] dig_spec.rb
- [ ] dup_spec.rb
- [ ] each_pair_spec.rb
- [ ] each_spec.rb
- [ ] element_reference_spec.rb
- [ ] element_set_spec.rb
- [ ] eql_spec.rb
- [ ] equal_value_spec.rb
- [ ] filter_spec.rb
- [ ] hash_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb
- [ ] instance_variable_get_spec.rb
- [ ] instance_variables_spec.rb
- [ ] keyword_init_spec.rb
- [ ] length_spec.rb
- [ ] members_spec.rb
- [ ] new_spec.rb
- [ ] select_spec.rb
- [ ] size_spec.rb
- [ ] struct_spec.rb
- [ ] to_a_spec.rb
- [ ] to_h_spec.rb
- [ ] to_s_spec.rb
- [ ] values_at_spec.rb
- [ ] values_spec.rb

### core/symbol
- [ ] all_symbols_spec.rb
- [ ] capitalize_spec.rb
- [ ] case_compare_spec.rb
- [ ] casecmp_spec.rb
- [ ] comparison_spec.rb
- [ ] downcase_spec.rb
- [ ] dup_spec.rb
- [ ] element_reference_spec.rb
- [ ] empty_spec.rb
- [ ] encoding_spec.rb
- [ ] end_with_spec.rb
- [ ] equal_value_spec.rb
- [ ] id2name_spec.rb
- [ ] inspect_spec.rb
- [ ] intern_spec.rb
- [x] length_spec.rb
- [ ] match_spec.rb
- [ ] name_spec.rb
- [ ] next_spec.rb
- [ ] size_spec.rb
- [ ] slice_spec.rb
- [ ] start_with_spec.rb
- [ ] succ_spec.rb
- [ ] swapcase_spec.rb
- [ ] symbol_spec.rb
- [ ] to_proc_spec.rb
- [x] to_s_spec.rb
- [x] to_sym_spec.rb
- [ ] upcase_spec.rb

### core/systemexit
- [ ] initialize_spec.rb
- [ ] success_spec.rb

### core/thread
- [ ] abort_on_exception_spec.rb
- [ ] add_trace_func_spec.rb
- [x] alive_spec.rb
- [ ] allocate_spec.rb

### core/thread/backtrace
- [ ] limit_spec.rb

### core/thread/backtrace/location
- [ ] absolute_path_spec.rb
- [ ] base_label_spec.rb
- [ ] inspect_spec.rb
- [ ] label_spec.rb
- [ ] lineno_spec.rb
- [ ] path_spec.rb
- [ ] to_s_spec.rb

### core/thread
- [ ] backtrace_locations_spec.rb
- [ ] backtrace_spec.rb
- [x] current_spec.rb
- [ ] each_caller_location_spec.rb
- [-] element_reference_spec.rb
- [-] element_set_spec.rb
- [ ] exit_spec.rb
- [ ] fetch_spec.rb
- [ ] fork_spec.rb
- [ ] group_spec.rb
- [ ] handle_interrupt_spec.rb
- [ ] ignore_deadlock_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb
- [x] join_spec.rb
- [ ] key_spec.rb
- [ ] keys_spec.rb
- [ ] kill_spec.rb
- [-] list_spec.rb
- [x] main_spec.rb
- [-] name_spec.rb
- [ ] native_thread_id_spec.rb
- [x] new_spec.rb
- [x] pass_spec.rb
- [ ] pending_interrupt_spec.rb
- [ ] priority_spec.rb
- [ ] raise_spec.rb
- [ ] report_on_exception_spec.rb
- [ ] run_spec.rb
- [ ] set_trace_func_spec.rb
- [ ] start_spec.rb
- [x] status_spec.rb
- [x] stop_spec.rb
- [ ] terminate_spec.rb
- [-] thread_variable_get_spec.rb
- [-] thread_variable_set_spec.rb
- [-] thread_variable_spec.rb
- [-] thread_variables_spec.rb
- [ ] to_s_spec.rb
- [-] value_spec.rb
- [ ] wakeup_spec.rb

### core/threadgroup
- [ ] add_spec.rb
- [ ] default_spec.rb
- [ ] enclose_spec.rb
- [ ] enclosed_spec.rb
- [ ] list_spec.rb

### core/time
- [ ] _dump_spec.rb
- [ ] _load_spec.rb
- [ ] asctime_spec.rb
- [ ] at_spec.rb
- [ ] ceil_spec.rb
- [ ] comparison_spec.rb
- [ ] ctime_spec.rb
- [ ] day_spec.rb
- [ ] deconstruct_keys_spec.rb
- [ ] dst_spec.rb
- [ ] dup_spec.rb
- [ ] eql_spec.rb
- [ ] floor_spec.rb
- [ ] friday_spec.rb
- [ ] getgm_spec.rb
- [ ] getlocal_spec.rb
- [ ] getutc_spec.rb
- [ ] gm_spec.rb
- [ ] gmt_offset_spec.rb
- [ ] gmt_spec.rb
- [ ] gmtime_spec.rb
- [ ] gmtoff_spec.rb
- [ ] hash_spec.rb
- [ ] hour_spec.rb
- [ ] inspect_spec.rb
- [ ] isdst_spec.rb
- [ ] iso8601_spec.rb
- [ ] local_spec.rb
- [ ] localtime_spec.rb
- [ ] mday_spec.rb
- [ ] min_spec.rb
- [ ] minus_spec.rb
- [ ] mktime_spec.rb
- [ ] mon_spec.rb
- [ ] monday_spec.rb
- [ ] month_spec.rb
- [ ] new_spec.rb
- [ ] now_spec.rb
- [ ] nsec_spec.rb
- [ ] plus_spec.rb
- [ ] round_spec.rb
- [ ] saturday_spec.rb
- [ ] sec_spec.rb
- [ ] strftime_spec.rb
- [ ] subsec_spec.rb
- [ ] sunday_spec.rb
- [ ] thursday_spec.rb
- [ ] time_spec.rb
- [ ] to_a_spec.rb
- [ ] to_f_spec.rb
- [ ] to_i_spec.rb
- [ ] to_r_spec.rb
- [ ] to_s_spec.rb
- [ ] tuesday_spec.rb
- [ ] tv_nsec_spec.rb
- [ ] tv_sec_spec.rb
- [ ] tv_usec_spec.rb
- [ ] usec_spec.rb
- [ ] utc_offset_spec.rb
- [ ] utc_spec.rb
- [ ] wday_spec.rb
- [ ] wednesday_spec.rb
- [ ] xmlschema_spec.rb
- [ ] yday_spec.rb
- [ ] year_spec.rb
- [ ] zone_spec.rb

### core/tracepoint
- [ ] allow_reentry_spec.rb
- [ ] binding_spec.rb
- [ ] callee_id_spec.rb
- [ ] defined_class_spec.rb
- [ ] disable_spec.rb
- [ ] enable_spec.rb
- [ ] enabled_spec.rb
- [ ] eval_script_spec.rb
- [ ] event_spec.rb
- [ ] inspect_spec.rb
- [ ] lineno_spec.rb
- [ ] method_id_spec.rb
- [ ] new_spec.rb
- [ ] parameters_spec.rb
- [ ] path_spec.rb
- [ ] raised_exception_spec.rb
- [ ] return_value_spec.rb
- [ ] self_spec.rb
- [ ] trace_spec.rb

### core/true
- [ ] and_spec.rb
- [ ] case_compare_spec.rb
- [ ] dup_spec.rb
- [x] inspect_spec.rb
- [ ] or_spec.rb
- [ ] singleton_method_spec.rb
- [ ] to_s_spec.rb
- [ ] trueclass_spec.rb
- [ ] xor_spec.rb

### core/unboundmethod
- [ ] arity_spec.rb
- [ ] bind_call_spec.rb
- [ ] bind_spec.rb
- [ ] clone_spec.rb
- [ ] dup_spec.rb
- [ ] eql_spec.rb
- [ ] equal_value_spec.rb
- [ ] hash_spec.rb
- [ ] inspect_spec.rb
- [ ] name_spec.rb
- [ ] original_name_spec.rb
- [ ] owner_spec.rb
- [ ] parameters_spec.rb
- [ ] private_spec.rb
- [ ] protected_spec.rb
- [ ] public_spec.rb
- [ ] source_location_spec.rb
- [ ] super_method_spec.rb
- [ ] to_s_spec.rb

### core/warning
- [ ] categories_spec.rb
- [ ] element_reference_spec.rb
- [ ] element_set_spec.rb
- [ ] performance_warning_spec.rb
- [ ] warn_spec.rb

### language
- [ ] BEGIN_spec.rb
- [ ] END_spec.rb
- [ ] alias_spec.rb
- [ ] and_spec.rb
- [ ] array_spec.rb
- [ ] assignments_spec.rb
- [ ] block_spec.rb
- [ ] break_spec.rb
- [ ] case_spec.rb
- [ ] class_spec.rb
- [ ] class_variable_spec.rb
- [ ] comment_spec.rb
- [ ] constants_spec.rb
- [ ] def_spec.rb
- [ ] defined_spec.rb
- [ ] delegation_spec.rb
- [ ] encoding_spec.rb
- [ ] ensure_spec.rb
- [ ] execution_spec.rb
- [ ] file_spec.rb
- [ ] for_spec.rb
- [ ] hash_spec.rb
- [ ] heredoc_spec.rb
- [ ] if_spec.rb
- [ ] it_parameter_spec.rb
- [ ] keyword_arguments_spec.rb
- [ ] lambda_spec.rb
- [ ] line_spec.rb
- [ ] loop_spec.rb
- [ ] magic_comment_spec.rb
- [ ] match_spec.rb
- [ ] metaclass_spec.rb
- [ ] method_spec.rb
- [ ] module_spec.rb
- [ ] next_spec.rb
- [ ] not_spec.rb
- [ ] numbered_parameters_spec.rb
- [ ] numbers_spec.rb
- [ ] optional_assignments_spec.rb
- [ ] or_spec.rb
- [ ] order_spec.rb
- [ ] pattern_matching_spec.rb
- [ ] precedence_spec.rb

### language/predefined
- [ ] data_spec.rb
- [ ] toplevel_binding_spec.rb

### language
- [ ] predefined_spec.rb
- [ ] private_spec.rb
- [ ] proc_spec.rb
- [ ] range_spec.rb
- [ ] redo_spec.rb

### language/regexp
- [ ] anchors_spec.rb
- [ ] back-references_spec.rb
- [ ] character_classes_spec.rb
- [ ] empty_checks_spec.rb
- [ ] encoding_spec.rb
- [ ] escapes_spec.rb
- [ ] grouping_spec.rb
- [ ] interpolation_spec.rb
- [ ] modifiers_spec.rb
- [ ] repetition_spec.rb
- [ ] subexpression_call_spec.rb

### language
- [ ] regexp_spec.rb
- [ ] rescue_spec.rb
- [ ] retry_spec.rb
- [ ] return_spec.rb
- [ ] safe_navigator_spec.rb
- [ ] safe_spec.rb
- [ ] send_spec.rb
- [ ] singleton_class_spec.rb
- [ ] source_encoding_spec.rb
- [ ] string_spec.rb
- [ ] super_spec.rb
- [ ] symbol_spec.rb
- [ ] throw_spec.rb
- [ ] undef_spec.rb
- [ ] unless_spec.rb
- [ ] until_spec.rb
- [ ] variables_spec.rb
- [ ] while_spec.rb
- [ ] yield_spec.rb

### library/English
- [ ] English_spec.rb
- [ ] alias_spec.rb

### library/abbrev
- [ ] abbrev_spec.rb

### library/base64
- [ ] decode64_spec.rb
- [ ] encode64_spec.rb
- [ ] strict_decode64_spec.rb
- [ ] strict_encode64_spec.rb
- [ ] urlsafe_decode64_spec.rb
- [ ] urlsafe_encode64_spec.rb

### library/bigdecimal
- [ ] BigDecimal_spec.rb
- [ ] abs_spec.rb
- [ ] add_spec.rb
- [ ] case_compare_spec.rb
- [ ] ceil_spec.rb
- [ ] clone_spec.rb
- [ ] coerce_spec.rb
- [ ] comparison_spec.rb
- [ ] constants_spec.rb
- [ ] core_spec.rb
- [ ] div_spec.rb
- [ ] divide_spec.rb
- [ ] divmod_spec.rb
- [ ] double_fig_spec.rb
- [ ] dup_spec.rb
- [ ] eql_spec.rb
- [ ] equal_value_spec.rb
- [ ] exponent_spec.rb
- [ ] finite_spec.rb
- [ ] fix_spec.rb
- [ ] floor_spec.rb
- [ ] frac_spec.rb
- [ ] gt_spec.rb
- [ ] gte_spec.rb
- [ ] hash_spec.rb
- [ ] infinite_spec.rb
- [ ] inspect_spec.rb
- [ ] limit_spec.rb
- [ ] lt_spec.rb
- [ ] lte_spec.rb
- [ ] minus_spec.rb
- [ ] mode_spec.rb
- [ ] modulo_spec.rb
- [ ] mult_spec.rb
- [ ] multiply_spec.rb
- [ ] nan_spec.rb
- [ ] nonzero_spec.rb
- [ ] plus_spec.rb
- [ ] power_spec.rb
- [ ] quo_spec.rb
- [ ] remainder_spec.rb
- [ ] round_spec.rb
- [ ] sign_spec.rb
- [ ] split_spec.rb
- [ ] sqrt_spec.rb
- [ ] sub_spec.rb
- [ ] to_d_spec.rb
- [ ] to_f_spec.rb
- [ ] to_i_spec.rb
- [ ] to_int_spec.rb
- [ ] to_r_spec.rb
- [ ] to_s_spec.rb
- [ ] truncate_spec.rb
- [ ] uminus_spec.rb
- [ ] uplus_spec.rb
- [ ] util_spec.rb
- [ ] zero_spec.rb

### library/cgi/cookie
- [ ] domain_spec.rb
- [ ] expires_spec.rb
- [ ] initialize_spec.rb
- [ ] name_spec.rb
- [ ] parse_spec.rb
- [ ] path_spec.rb
- [ ] secure_spec.rb
- [ ] to_s_spec.rb
- [ ] value_spec.rb

### library/cgi
- [ ] escapeElement_spec.rb
- [ ] escapeHTML_spec.rb
- [ ] escapeURIComponent_spec.rb
- [ ] escape_spec.rb

### library/cgi/htmlextension
- [ ] a_spec.rb
- [ ] base_spec.rb
- [ ] blockquote_spec.rb
- [ ] br_spec.rb
- [ ] caption_spec.rb
- [ ] checkbox_group_spec.rb
- [ ] checkbox_spec.rb
- [ ] doctype_spec.rb
- [ ] file_field_spec.rb
- [ ] form_spec.rb
- [ ] frame_spec.rb
- [ ] frameset_spec.rb
- [ ] hidden_spec.rb
- [ ] html_spec.rb
- [ ] image_button_spec.rb
- [ ] img_spec.rb
- [ ] multipart_form_spec.rb
- [ ] password_field_spec.rb
- [ ] popup_menu_spec.rb
- [ ] radio_button_spec.rb
- [ ] radio_group_spec.rb
- [ ] reset_spec.rb
- [ ] scrolling_list_spec.rb
- [ ] submit_spec.rb
- [ ] text_field_spec.rb
- [ ] textarea_spec.rb

### library/cgi
- [ ] http_header_spec.rb
- [ ] initialize_spec.rb
- [ ] out_spec.rb
- [ ] parse_spec.rb
- [ ] pretty_spec.rb
- [ ] print_spec.rb

### library/cgi/queryextension
- [ ] accept_charset_spec.rb
- [ ] accept_encoding_spec.rb
- [ ] accept_language_spec.rb
- [ ] accept_spec.rb
- [ ] auth_type_spec.rb
- [ ] cache_control_spec.rb
- [ ] content_length_spec.rb
- [ ] content_type_spec.rb
- [ ] cookies_spec.rb
- [ ] element_reference_spec.rb
- [ ] from_spec.rb
- [ ] gateway_interface_spec.rb
- [ ] has_key_spec.rb
- [ ] host_spec.rb
- [ ] include_spec.rb
- [ ] key_spec.rb
- [ ] keys_spec.rb
- [ ] multipart_spec.rb
- [ ] negotiate_spec.rb
- [ ] params_spec.rb
- [ ] path_info_spec.rb
- [ ] path_translated_spec.rb
- [ ] pragma_spec.rb
- [ ] query_string_spec.rb
- [ ] raw_cookie2_spec.rb
- [ ] raw_cookie_spec.rb
- [ ] referer_spec.rb
- [ ] remote_addr_spec.rb
- [ ] remote_host_spec.rb
- [ ] remote_ident_spec.rb
- [ ] remote_user_spec.rb
- [ ] request_method_spec.rb
- [ ] script_name_spec.rb
- [ ] server_name_spec.rb
- [ ] server_port_spec.rb
- [ ] server_protocol_spec.rb
- [ ] server_software_spec.rb
- [ ] user_agent_spec.rb

### library/cgi
- [ ] rfc1123_date_spec.rb
- [ ] unescapeElement_spec.rb
- [ ] unescapeHTML_spec.rb
- [ ] unescapeURIComponent_spec.rb
- [ ] unescape_spec.rb

### library/coverage
- [ ] peek_result_spec.rb
- [ ] result_spec.rb
- [ ] running_spec.rb
- [ ] start_spec.rb
- [ ] supported_spec.rb

### library/csv/basicwriter
- [ ] close_on_terminate_spec.rb
- [ ] initialize_spec.rb
- [ ] terminate_spec.rb

### library/csv/cell
- [ ] data_spec.rb
- [ ] initialize_spec.rb

### library/csv
- [ ] foreach_spec.rb
- [ ] generate_line_spec.rb
- [ ] generate_row_spec.rb
- [ ] generate_spec.rb

### library/csv/iobuf
- [ ] close_spec.rb
- [ ] initialize_spec.rb
- [ ] read_spec.rb
- [ ] terminate_spec.rb

### library/csv/ioreader
- [ ] close_on_terminate_spec.rb
- [ ] get_row_spec.rb
- [ ] initialize_spec.rb
- [ ] terminate_spec.rb

### library/csv
- [ ] liberal_parsing_spec.rb
- [ ] open_spec.rb
- [ ] parse_spec.rb
- [ ] read_spec.rb
- [ ] readlines_spec.rb

### library/csv/streambuf
- [ ] add_buf_spec.rb
- [ ] buf_size_spec.rb
- [ ] drop_spec.rb
- [ ] element_reference_spec.rb
- [ ] get_spec.rb
- [ ] idx_is_eos_spec.rb
- [ ] initialize_spec.rb
- [ ] is_eos_spec.rb
- [ ] read_spec.rb
- [ ] rel_buf_spec.rb
- [ ] terminate_spec.rb

### library/csv/stringreader
- [ ] get_row_spec.rb
- [ ] initialize_spec.rb

### library/csv/writer
- [ ] add_row_spec.rb
- [ ] append_spec.rb
- [ ] close_spec.rb
- [ ] create_spec.rb
- [ ] generate_spec.rb
- [ ] initialize_spec.rb
- [ ] terminate_spec.rb

### library/date
- [ ] accessor_spec.rb
- [ ] add_month_spec.rb
- [ ] add_spec.rb
- [ ] ajd_spec.rb
- [ ] ajd_to_amjd_spec.rb
- [ ] ajd_to_jd_spec.rb
- [ ] amjd_spec.rb
- [ ] amjd_to_ajd_spec.rb
- [ ] append_spec.rb
- [ ] asctime_spec.rb
- [ ] boat_spec.rb
- [ ] case_compare_spec.rb
- [ ] civil_spec.rb
- [ ] commercial_spec.rb
- [ ] commercial_to_jd_spec.rb
- [ ] comparison_spec.rb
- [ ] constants_spec.rb
- [ ] conversions_spec.rb
- [ ] ctime_spec.rb
- [ ] cwday_spec.rb
- [ ] cweek_spec.rb
- [ ] cwyear_spec.rb
- [ ] day_fraction_spec.rb
- [ ] day_fraction_to_time_spec.rb
- [ ] day_spec.rb
- [ ] deconstruct_keys_spec.rb
- [ ] downto_spec.rb
- [ ] england_spec.rb
- [ ] eql_spec.rb

### library/date/format/bag
- [ ] method_missing_spec.rb
- [ ] to_hash_spec.rb

### library/date
- [ ] friday_spec.rb
- [ ] gregorian_leap_spec.rb
- [ ] gregorian_spec.rb
- [ ] hash_spec.rb

### library/date/infinity
- [ ] abs_spec.rb
- [ ] coerce_spec.rb
- [ ] comparison_spec.rb
- [ ] d_spec.rb
- [ ] finite_spec.rb
- [ ] infinite_spec.rb
- [ ] nan_spec.rb
- [ ] uminus_spec.rb
- [ ] uplus_spec.rb
- [ ] zero_spec.rb

### library/date
- [ ] infinity_spec.rb
- [ ] inspect_spec.rb
- [ ] iso8601_spec.rb
- [ ] italy_spec.rb
- [ ] jd_spec.rb
- [ ] jd_to_ajd_spec.rb
- [ ] jd_to_civil_spec.rb
- [ ] jd_to_commercial_spec.rb
- [ ] jd_to_ld_spec.rb
- [ ] jd_to_mjd_spec.rb
- [ ] jd_to_ordinal_spec.rb
- [ ] jd_to_wday_spec.rb
- [ ] julian_leap_spec.rb
- [ ] julian_spec.rb
- [ ] ld_spec.rb
- [ ] ld_to_jd_spec.rb
- [ ] leap_spec.rb
- [ ] mday_spec.rb
- [ ] minus_month_spec.rb
- [ ] minus_spec.rb
- [ ] mjd_spec.rb
- [ ] mjd_to_jd_spec.rb
- [ ] mon_spec.rb
- [ ] monday_spec.rb
- [ ] month_spec.rb
- [ ] new_spec.rb
- [ ] new_start_spec.rb
- [ ] next_day_spec.rb
- [ ] next_month_spec.rb
- [ ] next_spec.rb
- [ ] next_year_spec.rb
- [ ] ordinal_spec.rb
- [ ] ordinal_to_jd_spec.rb
- [ ] parse_spec.rb
- [ ] plus_spec.rb
- [ ] prev_day_spec.rb
- [ ] prev_month_spec.rb
- [ ] prev_year_spec.rb
- [ ] relationship_spec.rb
- [ ] rfc3339_spec.rb
- [ ] right_shift_spec.rb
- [ ] saturday_spec.rb
- [ ] start_spec.rb
- [ ] step_spec.rb
- [ ] strftime_spec.rb
- [ ] strptime_spec.rb
- [ ] succ_spec.rb
- [ ] sunday_spec.rb
- [ ] thursday_spec.rb

### library/date/time
- [ ] to_date_spec.rb

### library/date
- [ ] time_to_day_fraction_spec.rb
- [ ] to_s_spec.rb
- [ ] today_spec.rb
- [ ] tuesday_spec.rb
- [ ] upto_spec.rb
- [ ] valid_civil_spec.rb
- [ ] valid_commercial_spec.rb
- [ ] valid_date_spec.rb
- [ ] valid_jd_spec.rb
- [ ] valid_ordinal_spec.rb
- [ ] valid_time_spec.rb
- [ ] wday_spec.rb
- [ ] wednesday_spec.rb
- [ ] yday_spec.rb
- [ ] year_spec.rb
- [ ] zone_to_diff_spec.rb

### library/datetime
- [ ] _strptime_spec.rb
- [ ] add_spec.rb
- [ ] civil_spec.rb
- [ ] commercial_spec.rb
- [ ] deconstruct_keys_spec.rb
- [ ] hour_spec.rb
- [ ] httpdate_spec.rb
- [ ] iso8601_spec.rb
- [ ] jd_spec.rb
- [ ] jisx0301_spec.rb
- [ ] min_spec.rb
- [ ] minute_spec.rb
- [ ] new_offset_spec.rb
- [ ] new_spec.rb
- [ ] now_spec.rb
- [ ] offset_spec.rb
- [ ] ordinal_spec.rb
- [ ] parse_spec.rb
- [ ] rfc2822_spec.rb
- [ ] rfc3339_spec.rb
- [ ] rfc822_spec.rb
- [ ] sec_fraction_spec.rb
- [ ] sec_spec.rb
- [ ] second_fraction_spec.rb
- [ ] second_spec.rb
- [ ] strftime_spec.rb
- [ ] strptime_spec.rb
- [ ] subtract_spec.rb

### library/datetime/time
- [ ] to_datetime_spec.rb

### library/datetime
- [ ] to_date_spec.rb
- [ ] to_datetime_spec.rb
- [ ] to_s_spec.rb
- [ ] to_time_spec.rb
- [ ] xmlschema_spec.rb
- [ ] yday_spec.rb
- [ ] zone_spec.rb

### library/delegate/delegate_class
- [ ] instance_method_spec.rb
- [ ] instance_methods_spec.rb
- [ ] private_instance_methods_spec.rb
- [ ] protected_instance_methods_spec.rb
- [ ] public_instance_methods_spec.rb
- [ ] respond_to_missing_spec.rb

### library/delegate/delegator
- [ ] case_compare_spec.rb
- [ ] compare_spec.rb
- [ ] complement_spec.rb
- [ ] eql_spec.rb
- [ ] equal_spec.rb
- [ ] equal_value_spec.rb
- [ ] frozen_spec.rb
- [ ] hash_spec.rb
- [ ] marshal_spec.rb
- [ ] method_spec.rb
- [ ] methods_spec.rb
- [ ] not_equal_spec.rb
- [ ] not_spec.rb
- [ ] private_methods_spec.rb
- [ ] protected_methods_spec.rb
- [ ] public_methods_spec.rb
- [ ] send_spec.rb
- [ ] taint_spec.rb
- [ ] tap_spec.rb
- [ ] trust_spec.rb
- [ ] untaint_spec.rb
- [ ] untrust_spec.rb

### library/digest
- [ ] bubblebabble_spec.rb
- [ ] hexencode_spec.rb

### library/digest/instance
- [ ] append_spec.rb
- [ ] new_spec.rb
- [ ] update_spec.rb

### library/digest/md5
- [ ] append_spec.rb
- [ ] block_length_spec.rb
- [ ] digest_bang_spec.rb
- [ ] digest_length_spec.rb
- [ ] digest_spec.rb
- [ ] equal_spec.rb
- [ ] file_spec.rb
- [ ] hexdigest_bang_spec.rb
- [ ] hexdigest_spec.rb
- [ ] inspect_spec.rb
- [ ] length_spec.rb
- [ ] reset_spec.rb
- [ ] size_spec.rb
- [ ] to_s_spec.rb
- [ ] update_spec.rb

### library/digest/sha1
- [ ] digest_spec.rb
- [ ] file_spec.rb

### library/digest/sha2
- [ ] hexdigest_spec.rb

### library/digest/sha256
- [ ] append_spec.rb
- [ ] block_length_spec.rb
- [ ] digest_bang_spec.rb
- [ ] digest_length_spec.rb
- [ ] digest_spec.rb
- [ ] equal_spec.rb
- [ ] file_spec.rb
- [ ] hexdigest_bang_spec.rb
- [ ] hexdigest_spec.rb
- [ ] inspect_spec.rb
- [ ] length_spec.rb
- [ ] reset_spec.rb
- [ ] size_spec.rb
- [ ] to_s_spec.rb
- [ ] update_spec.rb

### library/digest/sha384
- [ ] append_spec.rb
- [ ] block_length_spec.rb
- [ ] digest_bang_spec.rb
- [ ] digest_length_spec.rb
- [ ] digest_spec.rb
- [ ] equal_spec.rb
- [ ] file_spec.rb
- [ ] hexdigest_bang_spec.rb
- [ ] hexdigest_spec.rb
- [ ] inspect_spec.rb
- [ ] length_spec.rb
- [ ] reset_spec.rb
- [ ] size_spec.rb
- [ ] to_s_spec.rb
- [ ] update_spec.rb

### library/digest/sha512
- [ ] append_spec.rb
- [ ] block_length_spec.rb
- [ ] digest_bang_spec.rb
- [ ] digest_length_spec.rb
- [ ] digest_spec.rb
- [ ] equal_spec.rb
- [ ] file_spec.rb
- [ ] hexdigest_bang_spec.rb
- [ ] hexdigest_spec.rb
- [ ] inspect_spec.rb
- [ ] length_spec.rb
- [ ] reset_spec.rb
- [ ] size_spec.rb
- [ ] to_s_spec.rb
- [ ] update_spec.rb

### library/drb
- [ ] start_service_spec.rb

### library/erb
- [ ] def_class_spec.rb
- [ ] def_method_spec.rb
- [ ] def_module_spec.rb

### library/erb/defmethod
- [ ] def_erb_method_spec.rb

### library/erb
- [ ] filename_spec.rb
- [ ] new_spec.rb
- [ ] result_spec.rb
- [ ] run_spec.rb
- [ ] src_spec.rb

### library/erb/util
- [ ] h_spec.rb
- [ ] html_escape_spec.rb
- [ ] u_spec.rb
- [ ] url_encode_spec.rb

### library/etc
- [ ] confstr_spec.rb
- [ ] endgrent_spec.rb
- [ ] endpwent_spec.rb
- [ ] getgrent_spec.rb
- [ ] getgrgid_spec.rb
- [ ] getgrnam_spec.rb
- [ ] getlogin_spec.rb
- [ ] getpwent_spec.rb
- [ ] getpwnam_spec.rb
- [ ] getpwuid_spec.rb
- [ ] group_spec.rb
- [ ] nprocessors_spec.rb
- [ ] passwd_spec.rb
- [ ] struct_group_spec.rb
- [ ] struct_passwd_spec.rb
- [ ] sysconf_spec.rb
- [ ] sysconfdir_spec.rb
- [ ] systmpdir_spec.rb
- [ ] uname_spec.rb

### library/expect
- [ ] expect_spec.rb

### library/fiddle/handle
- [ ] initialize_spec.rb

### library/find
- [ ] find_spec.rb
- [ ] prune_spec.rb

### library/getoptlong
- [ ] each_option_spec.rb
- [ ] each_spec.rb
- [ ] error_message_spec.rb
- [ ] get_option_spec.rb
- [ ] get_spec.rb
- [ ] initialize_spec.rb
- [ ] ordering_spec.rb
- [ ] set_options_spec.rb
- [ ] terminate_spec.rb
- [ ] terminated_spec.rb

### library/io-wait
- [ ] wait_readable_spec.rb
- [ ] wait_spec.rb
- [ ] wait_writable_spec.rb

### library/ipaddr
- [ ] hton_spec.rb
- [ ] ipv4_conversion_spec.rb
- [ ] new_spec.rb
- [ ] operator_spec.rb
- [ ] reverse_spec.rb
- [ ] to_s_spec.rb

### library/irb
- [ ] irb_spec.rb

### library/logger/device
- [ ] close_spec.rb
- [ ] new_spec.rb
- [ ] write_spec.rb

### library/logger/logger
- [ ] add_spec.rb
- [ ] close_spec.rb
- [ ] datetime_format_spec.rb
- [ ] debug_spec.rb
- [ ] error_spec.rb
- [ ] fatal_spec.rb
- [ ] info_spec.rb
- [ ] new_spec.rb
- [ ] unknown_spec.rb
- [ ] warn_spec.rb

### library/logger
- [ ] severity_spec.rb

### library/matrix
- [ ] I_spec.rb
- [ ] antisymmetric_spec.rb
- [ ] build_spec.rb
- [ ] clone_spec.rb
- [ ] coerce_spec.rb
- [ ] collect_spec.rb
- [ ] column_size_spec.rb
- [ ] column_spec.rb
- [ ] column_vector_spec.rb
- [ ] column_vectors_spec.rb
- [ ] columns_spec.rb
- [ ] conj_spec.rb
- [ ] conjugate_spec.rb
- [ ] constructor_spec.rb
- [ ] det_spec.rb
- [ ] determinant_spec.rb
- [ ] diagonal_spec.rb
- [ ] divide_spec.rb
- [ ] each_spec.rb
- [ ] each_with_index_spec.rb

### library/matrix/eigenvalue_decomposition
- [ ] eigenvalue_matrix_spec.rb
- [ ] eigenvalues_spec.rb
- [ ] eigenvector_matrix_spec.rb
- [ ] eigenvectors_spec.rb
- [ ] initialize_spec.rb
- [ ] to_a_spec.rb

### library/matrix
- [ ] element_reference_spec.rb
- [ ] empty_spec.rb
- [ ] eql_spec.rb
- [ ] equal_value_spec.rb
- [ ] exponent_spec.rb
- [ ] find_index_spec.rb
- [ ] hash_spec.rb
- [ ] hermitian_spec.rb
- [ ] identity_spec.rb
- [ ] imag_spec.rb
- [ ] imaginary_spec.rb
- [ ] inspect_spec.rb
- [ ] inv_spec.rb
- [ ] inverse_from_spec.rb
- [ ] inverse_spec.rb
- [ ] lower_triangular_spec.rb

### library/matrix/lup_decomposition
- [ ] determinant_spec.rb
- [ ] initialize_spec.rb
- [ ] l_spec.rb
- [ ] p_spec.rb
- [ ] solve_spec.rb
- [ ] to_a_spec.rb
- [ ] u_spec.rb

### library/matrix
- [ ] map_spec.rb
- [ ] minor_spec.rb
- [ ] minus_spec.rb
- [ ] multiply_spec.rb
- [ ] new_spec.rb
- [ ] normal_spec.rb
- [ ] orthogonal_spec.rb
- [ ] permutation_spec.rb
- [ ] plus_spec.rb
- [ ] rank_spec.rb
- [ ] real_spec.rb
- [ ] rect_spec.rb
- [ ] rectangular_spec.rb
- [ ] regular_spec.rb
- [ ] round_spec.rb
- [ ] row_size_spec.rb
- [ ] row_spec.rb
- [ ] row_vector_spec.rb
- [ ] row_vectors_spec.rb
- [ ] rows_spec.rb

### library/matrix/scalar
- [ ] Fail_spec.rb
- [ ] Raise_spec.rb
- [ ] divide_spec.rb
- [ ] exponent_spec.rb
- [ ] included_spec.rb
- [ ] initialize_spec.rb
- [ ] minus_spec.rb
- [ ] multiply_spec.rb
- [ ] plus_spec.rb

### library/matrix
- [ ] scalar_spec.rb
- [ ] singular_spec.rb
- [ ] square_spec.rb
- [ ] symmetric_spec.rb
- [ ] t_spec.rb
- [ ] to_a_spec.rb
- [ ] to_s_spec.rb
- [ ] tr_spec.rb
- [ ] trace_spec.rb
- [ ] transpose_spec.rb
- [ ] unit_spec.rb
- [ ] unitary_spec.rb
- [ ] upper_triangular_spec.rb

### library/matrix/vector
- [ ] cross_product_spec.rb
- [ ] each2_spec.rb
- [ ] eql_spec.rb
- [ ] inner_product_spec.rb
- [ ] normalize_spec.rb

### library/matrix
- [ ] zero_spec.rb

### library/mkmf
- [ ] mkmf_spec.rb

### library/monitor
- [ ] enter_spec.rb
- [ ] exit_spec.rb
- [ ] mon_initialize_spec.rb
- [ ] new_cond_spec.rb
- [ ] synchronize_spec.rb
- [ ] try_enter_spec.rb

### library/net-ftp
- [ ] FTPError_spec.rb
- [ ] FTPPermError_spec.rb
- [ ] FTPProtoError_spec.rb
- [ ] FTPReplyError_spec.rb
- [ ] FTPTempError_spec.rb
- [ ] abort_spec.rb
- [ ] acct_spec.rb
- [ ] binary_spec.rb
- [ ] chdir_spec.rb
- [ ] close_spec.rb
- [ ] closed_spec.rb
- [ ] connect_spec.rb
- [ ] debug_mode_spec.rb
- [ ] default_passive_spec.rb
- [ ] delete_spec.rb
- [ ] dir_spec.rb
- [ ] get_spec.rb
- [ ] getbinaryfile_spec.rb
- [ ] getdir_spec.rb
- [ ] gettextfile_spec.rb
- [ ] help_spec.rb
- [ ] initialize_spec.rb
- [ ] last_response_code_spec.rb
- [ ] last_response_spec.rb
- [ ] lastresp_spec.rb
- [ ] list_spec.rb
- [ ] login_spec.rb
- [ ] ls_spec.rb
- [ ] mdtm_spec.rb
- [ ] mkdir_spec.rb
- [ ] mtime_spec.rb
- [ ] nlst_spec.rb
- [ ] noop_spec.rb
- [ ] open_spec.rb
- [ ] passive_spec.rb
- [ ] put_spec.rb
- [ ] putbinaryfile_spec.rb
- [ ] puttextfile_spec.rb
- [ ] pwd_spec.rb
- [ ] quit_spec.rb
- [ ] rename_spec.rb
- [ ] resume_spec.rb
- [ ] retrbinary_spec.rb
- [ ] retrlines_spec.rb
- [ ] return_code_spec.rb
- [ ] rmdir_spec.rb
- [ ] sendcmd_spec.rb
- [ ] set_socket_spec.rb
- [ ] site_spec.rb
- [ ] size_spec.rb
- [ ] status_spec.rb
- [ ] storbinary_spec.rb
- [ ] storlines_spec.rb
- [ ] system_spec.rb
- [ ] voidcmd_spec.rb
- [ ] welcome_spec.rb

### library/net-http
- [ ] HTTPBadResponse_spec.rb
- [ ] HTTPClientExcepton_spec.rb
- [ ] HTTPError_spec.rb
- [ ] HTTPFatalError_spec.rb
- [ ] HTTPHeaderSyntaxError_spec.rb
- [ ] HTTPRetriableError_spec.rb
- [ ] HTTPServerException_spec.rb

### library/net-http/http
- [ ] Proxy_spec.rb
- [ ] active_spec.rb
- [ ] address_spec.rb
- [ ] close_on_empty_response_spec.rb
- [ ] copy_spec.rb
- [ ] default_port_spec.rb
- [ ] delete_spec.rb
- [ ] finish_spec.rb
- [ ] get2_spec.rb
- [ ] get_print_spec.rb
- [ ] get_response_spec.rb
- [ ] get_spec.rb
- [ ] head2_spec.rb
- [ ] head_spec.rb
- [ ] http_default_port_spec.rb
- [ ] https_default_port_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb
- [ ] is_version_1_1_spec.rb
- [ ] is_version_1_2_spec.rb
- [ ] lock_spec.rb
- [ ] mkcol_spec.rb
- [ ] move_spec.rb
- [ ] new_spec.rb
- [ ] newobj_spec.rb
- [ ] open_timeout_spec.rb
- [ ] options_spec.rb
- [ ] port_spec.rb
- [ ] post2_spec.rb
- [ ] post_form_spec.rb
- [ ] post_spec.rb
- [ ] propfind_spec.rb
- [ ] proppatch_spec.rb
- [ ] proxy_address_spec.rb
- [ ] proxy_class_spec.rb
- [ ] proxy_pass_spec.rb
- [ ] proxy_port_spec.rb
- [ ] proxy_user_spec.rb
- [ ] put2_spec.rb
- [ ] put_spec.rb
- [ ] read_timeout_spec.rb
- [ ] request_get_spec.rb
- [ ] request_head_spec.rb
- [ ] request_post_spec.rb
- [ ] request_put_spec.rb
- [ ] request_spec.rb
- [ ] request_types_spec.rb
- [ ] send_request_spec.rb
- [ ] set_debug_output_spec.rb
- [ ] socket_type_spec.rb
- [ ] start_spec.rb
- [ ] started_spec.rb
- [ ] trace_spec.rb
- [ ] unlock_spec.rb
- [ ] use_ssl_spec.rb
- [ ] version_1_1_spec.rb
- [ ] version_1_2_spec.rb

### library/net-http/httpexceptions
- [ ] initialize_spec.rb
- [ ] response_spec.rb

### library/net-http/httpgenericrequest
- [ ] body_exist_spec.rb
- [ ] body_spec.rb
- [ ] body_stream_spec.rb
- [ ] exec_spec.rb
- [ ] inspect_spec.rb
- [ ] method_spec.rb
- [ ] path_spec.rb
- [ ] request_body_permitted_spec.rb
- [ ] response_body_permitted_spec.rb
- [ ] set_body_internal_spec.rb

### library/net-http/httpheader
- [ ] add_field_spec.rb
- [ ] basic_auth_spec.rb
- [ ] canonical_each_spec.rb
- [ ] chunked_spec.rb
- [ ] content_length_spec.rb
- [ ] content_range_spec.rb
- [ ] content_type_spec.rb
- [ ] delete_spec.rb
- [ ] each_capitalized_name_spec.rb
- [ ] each_capitalized_spec.rb
- [ ] each_header_spec.rb
- [ ] each_key_spec.rb
- [ ] each_name_spec.rb
- [ ] each_spec.rb
- [ ] each_value_spec.rb
- [ ] element_reference_spec.rb
- [ ] element_set_spec.rb
- [ ] fetch_spec.rb
- [ ] form_data_spec.rb
- [ ] get_fields_spec.rb
- [ ] initialize_http_header_spec.rb
- [ ] key_spec.rb
- [ ] length_spec.rb
- [ ] main_type_spec.rb
- [ ] proxy_basic_auth_spec.rb
- [ ] range_length_spec.rb
- [ ] range_spec.rb
- [ ] set_content_type_spec.rb
- [ ] set_form_data_spec.rb
- [ ] set_range_spec.rb
- [ ] size_spec.rb
- [ ] sub_type_spec.rb
- [ ] to_hash_spec.rb
- [ ] type_params_spec.rb

### library/net-http/httprequest
- [ ] initialize_spec.rb

### library/net-http/httpresponse
- [ ] body_permitted_spec.rb
- [ ] body_spec.rb
- [ ] code_spec.rb
- [ ] code_type_spec.rb
- [ ] entity_spec.rb
- [ ] error_spec.rb
- [ ] error_type_spec.rb
- [ ] exception_type_spec.rb
- [ ] header_spec.rb
- [ ] http_version_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb
- [ ] message_spec.rb
- [ ] msg_spec.rb
- [ ] read_body_spec.rb
- [ ] read_header_spec.rb
- [ ] read_new_spec.rb
- [ ] reading_body_spec.rb
- [ ] response_spec.rb
- [ ] value_spec.rb

### library/objectspace
- [ ] dump_all_spec.rb
- [ ] dump_spec.rb
- [ ] memsize_of_all_spec.rb
- [ ] memsize_of_spec.rb
- [ ] reachable_objects_from_spec.rb
- [ ] trace_object_allocations_spec.rb
- [ ] trace_spec.rb

### library/observer
- [ ] add_observer_spec.rb
- [ ] count_observers_spec.rb
- [ ] delete_observer_spec.rb
- [ ] delete_observers_spec.rb
- [ ] notify_observers_spec.rb

### library/open3
- [ ] capture2_spec.rb
- [ ] capture2e_spec.rb
- [ ] capture3_spec.rb
- [ ] pipeline_r_spec.rb
- [ ] pipeline_rw_spec.rb
- [ ] pipeline_spec.rb
- [ ] pipeline_start_spec.rb
- [ ] pipeline_w_spec.rb
- [ ] popen2_spec.rb
- [ ] popen2e_spec.rb
- [ ] popen3_spec.rb

### library/openssl
- [ ] cipher_spec.rb

### library/openssl/digest
- [ ] append_spec.rb
- [ ] block_length_spec.rb
- [ ] digest_length_spec.rb
- [ ] digest_spec.rb
- [ ] initialize_spec.rb
- [ ] name_spec.rb
- [ ] reset_spec.rb
- [ ] update_spec.rb

### library/openssl
- [ ] fixed_length_secure_compare_spec.rb

### library/openssl/hmac
- [ ] digest_spec.rb
- [ ] hexdigest_spec.rb

### library/openssl/kdf
- [ ] pbkdf2_hmac_spec.rb
- [ ] scrypt_spec.rb

### library/openssl/random
- [ ] pseudo_bytes_spec.rb
- [ ] random_bytes_spec.rb

### library/openssl
- [ ] secure_compare_spec.rb

### library/openssl/x509/name
- [ ] parse_spec.rb

### library/openssl/x509/store
- [ ] verify_spec.rb

### library/openstruct
- [ ] delete_field_spec.rb
- [ ] element_reference_spec.rb
- [ ] element_set_spec.rb
- [ ] equal_value_spec.rb
- [ ] frozen_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb
- [ ] marshal_dump_spec.rb
- [ ] marshal_load_spec.rb
- [ ] method_missing_spec.rb
- [ ] new_spec.rb
- [ ] to_h_spec.rb
- [ ] to_s_spec.rb

### library/optionparser
- [ ] order_spec.rb
- [ ] parse_spec.rb

### library/pathname
- [ ] absolute_spec.rb
- [ ] birthtime_spec.rb
- [ ] divide_spec.rb
- [ ] empty_spec.rb
- [ ] equal_value_spec.rb
- [ ] glob_spec.rb
- [ ] hash_spec.rb
- [ ] inspect_spec.rb
- [ ] join_spec.rb
- [ ] new_spec.rb
- [ ] parent_spec.rb
- [ ] pathname_spec.rb
- [ ] plus_spec.rb
- [ ] realdirpath_spec.rb
- [ ] realpath_spec.rb
- [ ] relative_path_from_spec.rb
- [ ] relative_spec.rb
- [ ] root_spec.rb
- [ ] sub_spec.rb

### library/pp
- [ ] pp_spec.rb

### library/prime
- [ ] each_spec.rb
- [ ] instance_spec.rb
- [ ] int_from_prime_division_spec.rb

### library/prime/integer
- [ ] each_prime_spec.rb
- [ ] from_prime_division_spec.rb
- [ ] prime_division_spec.rb
- [ ] prime_spec.rb

### library/prime
- [ ] next_spec.rb
- [ ] prime_division_spec.rb
- [ ] prime_spec.rb
- [ ] succ_spec.rb

### library/random/formatter
- [ ] alphanumeric_spec.rb

### library/rbconfig
- [ ] rbconfig_spec.rb

### library/rbconfig/sizeof
- [ ] limits_spec.rb
- [ ] sizeof_spec.rb

### library/rbconfig
- [ ] unicode_emoji_version_spec.rb
- [ ] unicode_version_spec.rb

### library/readline
- [ ] basic_quote_characters_spec.rb
- [ ] basic_word_break_characters_spec.rb
- [ ] completer_quote_characters_spec.rb
- [ ] completer_word_break_characters_spec.rb
- [ ] completion_append_character_spec.rb
- [ ] completion_case_fold_spec.rb
- [ ] completion_proc_spec.rb
- [ ] constants_spec.rb
- [ ] emacs_editing_mode_spec.rb
- [ ] filename_quote_characters_spec.rb

### library/readline/history
- [ ] append_spec.rb
- [ ] delete_at_spec.rb
- [ ] each_spec.rb
- [ ] element_reference_spec.rb
- [ ] element_set_spec.rb
- [ ] empty_spec.rb
- [ ] history_spec.rb
- [ ] length_spec.rb
- [ ] pop_spec.rb
- [ ] push_spec.rb
- [ ] shift_spec.rb
- [ ] size_spec.rb
- [ ] to_s_spec.rb

### library/readline
- [ ] readline_spec.rb
- [ ] vi_editing_mode_spec.rb

### library/resolv
- [ ] get_address_spec.rb
- [ ] get_addresses_spec.rb
- [ ] get_name_spec.rb
- [ ] get_names_spec.rb

### library/ripper
- [ ] lex_spec.rb
- [ ] sexp_spec.rb

### library/rubygems/gem
- [ ] bin_path_spec.rb
- [ ] load_path_insert_index_spec.rb

### library/securerandom
- [ ] base64_spec.rb
- [ ] bytes_spec.rb
- [ ] hex_spec.rb
- [ ] random_bytes_spec.rb
- [ ] random_number_spec.rb

### library/shellwords
- [ ] shellwords_spec.rb

### library/singleton
- [ ] allocate_spec.rb
- [ ] clone_spec.rb
- [ ] dump_spec.rb
- [ ] dup_spec.rb
- [ ] instance_spec.rb
- [ ] load_spec.rb
- [ ] new_spec.rb

### library/socket/addrinfo
- [ ] afamily_spec.rb
- [ ] bind_spec.rb
- [ ] canonname_spec.rb
- [ ] connect_from_spec.rb
- [ ] connect_spec.rb
- [ ] connect_to_spec.rb
- [ ] family_addrinfo_spec.rb
- [ ] foreach_spec.rb
- [ ] getaddrinfo_spec.rb
- [ ] getnameinfo_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_sockaddr_spec.rb
- [ ] inspect_spec.rb
- [ ] ip_address_spec.rb
- [ ] ip_port_spec.rb
- [ ] ip_spec.rb
- [ ] ip_unpack_spec.rb
- [ ] ipv4_loopback_spec.rb
- [ ] ipv4_multicast_spec.rb
- [ ] ipv4_private_spec.rb
- [ ] ipv4_spec.rb
- [ ] ipv6_linklocal_spec.rb
- [ ] ipv6_loopback_spec.rb
- [ ] ipv6_mc_global_spec.rb
- [ ] ipv6_mc_linklocal_spec.rb
- [ ] ipv6_mc_nodelocal_spec.rb
- [ ] ipv6_mc_orglocal_spec.rb
- [ ] ipv6_mc_sitelocal_spec.rb
- [ ] ipv6_multicast_spec.rb
- [ ] ipv6_sitelocal_spec.rb
- [ ] ipv6_spec.rb
- [ ] ipv6_to_ipv4_spec.rb
- [ ] ipv6_unique_local_spec.rb
- [ ] ipv6_unspecified_spec.rb
- [ ] ipv6_v4compat_spec.rb
- [ ] ipv6_v4mapped_spec.rb
- [ ] listen_spec.rb
- [ ] marshal_dump_spec.rb
- [ ] marshal_load_spec.rb
- [ ] pfamily_spec.rb
- [ ] protocol_spec.rb
- [ ] socktype_spec.rb
- [ ] tcp_spec.rb
- [ ] to_s_spec.rb
- [ ] to_sockaddr_spec.rb
- [ ] udp_spec.rb
- [ ] unix_path_spec.rb
- [ ] unix_spec.rb

### library/socket/ancillarydata
- [ ] cmsg_is_spec.rb
- [ ] data_spec.rb
- [ ] family_spec.rb
- [ ] initialize_spec.rb
- [ ] int_spec.rb
- [ ] ip_pktinfo_spec.rb
- [ ] ipv6_pktinfo_addr_spec.rb
- [ ] ipv6_pktinfo_ifindex_spec.rb
- [ ] ipv6_pktinfo_spec.rb
- [ ] level_spec.rb
- [ ] type_spec.rb
- [ ] unix_rights_spec.rb

### library/socket/basicsocket
- [ ] close_read_spec.rb
- [ ] close_write_spec.rb
- [ ] connect_address_spec.rb
- [ ] do_not_reverse_lookup_spec.rb
- [ ] for_fd_spec.rb
- [ ] getpeereid_spec.rb
- [ ] getpeername_spec.rb
- [ ] getsockname_spec.rb
- [ ] getsockopt_spec.rb
- [ ] ioctl_spec.rb
- [ ] local_address_spec.rb
- [ ] read_nonblock_spec.rb
- [ ] read_spec.rb
- [ ] recv_nonblock_spec.rb
- [ ] recv_spec.rb
- [ ] recvmsg_nonblock_spec.rb
- [ ] recvmsg_spec.rb
- [ ] remote_address_spec.rb
- [ ] send_spec.rb
- [ ] sendmsg_nonblock_spec.rb
- [ ] sendmsg_spec.rb
- [ ] setsockopt_spec.rb
- [ ] shutdown_spec.rb
- [ ] write_nonblock_spec.rb

### library/socket/constants
- [ ] constants_spec.rb

### library/socket/ipsocket
- [ ] addr_spec.rb
- [ ] getaddress_spec.rb
- [ ] peeraddr_spec.rb
- [ ] recvfrom_spec.rb

### library/socket/option
- [ ] bool_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb
- [ ] int_spec.rb
- [ ] linger_spec.rb
- [ ] new_spec.rb

### library/socket/socket
- [ ] accept_loop_spec.rb
- [ ] accept_nonblock_spec.rb
- [ ] accept_spec.rb
- [ ] bind_spec.rb
- [ ] connect_nonblock_spec.rb
- [ ] connect_spec.rb
- [ ] for_fd_spec.rb
- [ ] getaddrinfo_spec.rb
- [ ] gethostbyaddr_spec.rb
- [ ] gethostbyname_spec.rb
- [ ] gethostname_spec.rb
- [ ] getifaddrs_spec.rb
- [ ] getnameinfo_spec.rb
- [ ] getservbyname_spec.rb
- [ ] getservbyport_spec.rb
- [ ] initialize_spec.rb
- [ ] ip_address_list_spec.rb
- [ ] ipv6only_bang_spec.rb
- [ ] listen_spec.rb
- [ ] local_address_spec.rb
- [ ] pack_sockaddr_in_spec.rb
- [ ] pack_sockaddr_un_spec.rb
- [ ] pair_spec.rb
- [ ] recvfrom_nonblock_spec.rb
- [ ] recvfrom_spec.rb
- [ ] remote_address_spec.rb
- [ ] sockaddr_in_spec.rb
- [ ] sockaddr_un_spec.rb
- [ ] socket_spec.rb
- [ ] socketpair_spec.rb
- [ ] sysaccept_spec.rb
- [ ] tcp_server_loop_spec.rb
- [ ] tcp_server_sockets_spec.rb
- [ ] tcp_spec.rb
- [ ] udp_server_loop_on_spec.rb
- [ ] udp_server_loop_spec.rb
- [ ] udp_server_recv_spec.rb
- [ ] udp_server_sockets_spec.rb
- [ ] unix_server_loop_spec.rb
- [ ] unix_server_socket_spec.rb
- [ ] unix_spec.rb
- [ ] unpack_sockaddr_in_spec.rb
- [ ] unpack_sockaddr_un_spec.rb

### library/socket/tcpserver
- [ ] accept_nonblock_spec.rb
- [ ] accept_spec.rb
- [ ] gets_spec.rb
- [ ] initialize_spec.rb
- [ ] listen_spec.rb
- [ ] new_spec.rb
- [ ] sysaccept_spec.rb

### library/socket/tcpsocket
- [ ] gethostbyname_spec.rb
- [ ] initialize_spec.rb
- [ ] local_address_spec.rb
- [ ] open_spec.rb
- [ ] partially_closable_spec.rb
- [ ] recv_nonblock_spec.rb
- [ ] recv_spec.rb
- [ ] remote_address_spec.rb
- [ ] setsockopt_spec.rb

### library/socket/udpsocket
- [ ] bind_spec.rb
- [ ] connect_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb
- [ ] local_address_spec.rb
- [ ] new_spec.rb
- [ ] open_spec.rb
- [ ] recvfrom_nonblock_spec.rb
- [ ] remote_address_spec.rb
- [ ] send_spec.rb
- [ ] write_spec.rb

### library/socket/unixserver
- [ ] accept_nonblock_spec.rb
- [ ] accept_spec.rb
- [ ] for_fd_spec.rb
- [ ] initialize_spec.rb
- [ ] listen_spec.rb
- [ ] new_spec.rb
- [ ] open_spec.rb
- [ ] sysaccept_spec.rb

### library/socket/unixsocket
- [ ] addr_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb
- [ ] local_address_spec.rb
- [ ] new_spec.rb
- [ ] open_spec.rb
- [ ] pair_spec.rb
- [ ] partially_closable_spec.rb
- [ ] path_spec.rb
- [ ] peeraddr_spec.rb
- [ ] recv_io_spec.rb
- [ ] recvfrom_spec.rb
- [ ] remote_address_spec.rb
- [ ] send_io_spec.rb
- [ ] socketpair_spec.rb

### library/stringio
- [ ] append_spec.rb
- [ ] binmode_spec.rb
- [ ] close_read_spec.rb
- [ ] close_spec.rb
- [ ] close_write_spec.rb
- [ ] closed_read_spec.rb
- [ ] closed_spec.rb
- [ ] closed_write_spec.rb
- [ ] each_byte_spec.rb
- [ ] each_char_spec.rb
- [ ] each_codepoint_spec.rb
- [ ] each_line_spec.rb
- [ ] each_spec.rb
- [ ] eof_spec.rb
- [ ] external_encoding_spec.rb
- [ ] fcntl_spec.rb
- [ ] fileno_spec.rb
- [ ] flush_spec.rb
- [ ] fsync_spec.rb
- [ ] getbyte_spec.rb
- [ ] getc_spec.rb
- [ ] getch_spec.rb
- [ ] getpass_spec.rb
- [ ] gets_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb
- [ ] internal_encoding_spec.rb
- [ ] isatty_spec.rb
- [ ] length_spec.rb
- [ ] lineno_spec.rb
- [ ] new_spec.rb
- [ ] open_spec.rb
- [ ] path_spec.rb
- [ ] pid_spec.rb
- [ ] pos_spec.rb
- [ ] print_spec.rb
- [ ] printf_spec.rb
- [ ] putc_spec.rb
- [ ] puts_spec.rb
- [ ] read_nonblock_spec.rb
- [ ] read_spec.rb
- [ ] readbyte_spec.rb
- [ ] readchar_spec.rb
- [ ] readline_spec.rb
- [ ] readlines_spec.rb
- [ ] readpartial_spec.rb
- [ ] reopen_spec.rb
- [ ] rewind_spec.rb
- [ ] seek_spec.rb
- [ ] set_encoding_by_bom_spec.rb
- [ ] set_encoding_spec.rb
- [ ] size_spec.rb
- [ ] string_spec.rb
- [ ] stringio_spec.rb
- [ ] sync_spec.rb
- [ ] sysread_spec.rb
- [ ] syswrite_spec.rb
- [ ] tell_spec.rb
- [ ] truncate_spec.rb
- [ ] tty_spec.rb
- [ ] ungetbyte_spec.rb
- [ ] ungetc_spec.rb
- [ ] write_nonblock_spec.rb
- [ ] write_spec.rb

### library/stringscanner
- [ ] append_spec.rb
- [ ] beginning_of_line_spec.rb
- [ ] bol_spec.rb
- [ ] captures_spec.rb
- [ ] charpos_spec.rb
- [ ] check_spec.rb
- [ ] check_until_spec.rb
- [ ] concat_spec.rb
- [ ] dup_spec.rb
- [ ] element_reference_spec.rb
- [ ] eos_spec.rb
- [ ] exist_spec.rb
- [ ] fixed_anchor_spec.rb
- [ ] get_byte_spec.rb
- [ ] getch_spec.rb
- [ ] initialize_spec.rb
- [ ] inspect_spec.rb
- [ ] match_spec.rb
- [ ] matched_size_spec.rb
- [ ] matched_spec.rb
- [ ] must_C_version_spec.rb
- [ ] named_captures_spec.rb
- [ ] peek_byte_spec.rb
- [ ] peek_spec.rb
- [ ] pointer_spec.rb
- [ ] pos_spec.rb
- [ ] post_match_spec.rb
- [ ] pre_match_spec.rb
- [ ] reset_spec.rb
- [ ] rest_size_spec.rb
- [ ] rest_spec.rb
- [ ] scan_byte_spec.rb
- [ ] scan_full_spec.rb
- [ ] scan_integer_spec.rb
- [ ] scan_spec.rb
- [ ] scan_until_spec.rb
- [ ] search_full_spec.rb
- [ ] size_spec.rb
- [ ] skip_spec.rb
- [ ] skip_until_spec.rb
- [ ] string_spec.rb
- [ ] terminate_spec.rb
- [ ] unscan_spec.rb
- [ ] values_at_spec.rb

### library/syslog
- [ ] alert_spec.rb
- [ ] close_spec.rb
- [ ] constants_spec.rb
- [ ] crit_spec.rb
- [ ] debug_spec.rb
- [ ] emerg_spec.rb
- [ ] err_spec.rb
- [ ] facility_spec.rb
- [ ] ident_spec.rb
- [ ] info_spec.rb
- [ ] inspect_spec.rb
- [ ] instance_spec.rb
- [ ] log_spec.rb
- [ ] mask_spec.rb
- [ ] notice_spec.rb
- [ ] open_spec.rb
- [ ] opened_spec.rb
- [ ] options_spec.rb
- [ ] reopen_spec.rb
- [ ] warning_spec.rb

### library/tempfile
- [ ] _close_spec.rb
- [ ] close_spec.rb
- [ ] create_spec.rb
- [ ] delete_spec.rb
- [ ] initialize_spec.rb
- [ ] length_spec.rb
- [ ] open_spec.rb
- [ ] path_spec.rb
- [ ] size_spec.rb
- [ ] unlink_spec.rb

### library/thread
- [ ] queue_spec.rb
- [ ] sizedqueue_spec.rb

### library/time
- [ ] httpdate_spec.rb
- [ ] iso8601_spec.rb
- [ ] rfc2822_spec.rb
- [ ] rfc822_spec.rb
- [ ] to_time_spec.rb
- [ ] xmlschema_spec.rb

### library/timeout
- [ ] error_spec.rb
- [ ] timeout_spec.rb

### library/tmpdir/dir
- [ ] mktmpdir_spec.rb
- [ ] tmpdir_spec.rb

### library/uri
- [ ] decode_www_form_component_spec.rb
- [ ] decode_www_form_spec.rb
- [ ] encode_www_form_component_spec.rb
- [ ] encode_www_form_spec.rb
- [ ] eql_spec.rb
- [ ] equality_spec.rb

### library/uri/escape
- [ ] decode_spec.rb
- [ ] encode_spec.rb
- [ ] escape_spec.rb
- [ ] unescape_spec.rb

### library/uri
- [ ] extract_spec.rb

### library/uri/ftp
- [ ] build_spec.rb
- [ ] merge_spec.rb
- [ ] new2_spec.rb
- [ ] path_spec.rb
- [ ] set_typecode_spec.rb
- [ ] to_s_spec.rb
- [ ] typecode_spec.rb

### library/uri/generic
- [ ] absolute_spec.rb
- [ ] build2_spec.rb
- [ ] build_spec.rb
- [ ] coerce_spec.rb
- [ ] component_ary_spec.rb
- [ ] component_spec.rb
- [ ] default_port_spec.rb
- [ ] eql_spec.rb
- [ ] equal_value_spec.rb
- [ ] fragment_spec.rb
- [ ] hash_spec.rb
- [ ] hierarchical_spec.rb
- [ ] host_spec.rb
- [ ] inspect_spec.rb
- [ ] merge_spec.rb
- [ ] minus_spec.rb
- [ ] normalize_spec.rb
- [ ] opaque_spec.rb
- [ ] password_spec.rb
- [ ] path_spec.rb
- [ ] plus_spec.rb
- [ ] port_spec.rb
- [ ] query_spec.rb
- [ ] registry_spec.rb
- [ ] relative_spec.rb
- [ ] route_from_spec.rb
- [ ] route_to_spec.rb
- [ ] scheme_spec.rb
- [ ] select_spec.rb
- [ ] set_fragment_spec.rb
- [ ] set_host_spec.rb
- [ ] set_opaque_spec.rb
- [ ] set_password_spec.rb
- [ ] set_path_spec.rb
- [ ] set_port_spec.rb
- [ ] set_query_spec.rb
- [ ] set_registry_spec.rb
- [ ] set_scheme_spec.rb
- [ ] set_user_spec.rb
- [ ] set_userinfo_spec.rb
- [ ] to_s_spec.rb
- [ ] use_registry_spec.rb
- [ ] user_spec.rb
- [ ] userinfo_spec.rb

### library/uri/http
- [ ] build_spec.rb
- [ ] request_uri_spec.rb

### library/uri
- [ ] join_spec.rb

### library/uri/ldap
- [ ] attributes_spec.rb
- [ ] build_spec.rb
- [ ] dn_spec.rb
- [ ] extensions_spec.rb
- [ ] filter_spec.rb
- [ ] hierarchical_spec.rb
- [ ] scope_spec.rb
- [ ] set_attributes_spec.rb
- [ ] set_dn_spec.rb
- [ ] set_extensions_spec.rb
- [ ] set_filter_spec.rb
- [ ] set_scope_spec.rb

### library/uri/mailto
- [ ] build_spec.rb
- [ ] headers_spec.rb
- [ ] set_headers_spec.rb
- [ ] set_to_spec.rb
- [ ] to_mailtext_spec.rb
- [ ] to_rfc822text_spec.rb
- [ ] to_s_spec.rb
- [ ] to_spec.rb

### library/uri
- [ ] merge_spec.rb
- [ ] normalize_spec.rb
- [ ] parse_spec.rb

### library/uri/parser
- [ ] escape_spec.rb
- [ ] extract_spec.rb
- [ ] inspect_spec.rb
- [ ] join_spec.rb
- [ ] make_regexp_spec.rb
- [ ] parse_spec.rb
- [ ] split_spec.rb
- [ ] unescape_spec.rb

### library/uri
- [ ] plus_spec.rb
- [ ] regexp_spec.rb
- [ ] route_from_spec.rb
- [ ] route_to_spec.rb
- [ ] select_spec.rb
- [ ] set_component_spec.rb
- [ ] split_spec.rb
- [ ] uri_spec.rb

### library/uri/util
- [ ] make_components_hash_spec.rb

### library/weakref
- [ ] __getobj___spec.rb
- [ ] allocate_spec.rb
- [ ] new_spec.rb
- [ ] send_spec.rb
- [ ] weakref_alive_spec.rb

### library/win32ole/win32ole
- [ ] _getproperty_spec.rb
- [ ] _invoke_spec.rb
- [ ] codepage_spec.rb
- [ ] connect_spec.rb
- [ ] const_load_spec.rb
- [ ] constants_spec.rb
- [ ] create_guid_spec.rb
- [ ] invoke_spec.rb
- [ ] locale_spec.rb
- [ ] new_spec.rb
- [ ] ole_func_methods_spec.rb
- [ ] ole_get_methods_spec.rb
- [ ] ole_method_help_spec.rb
- [ ] ole_method_spec.rb
- [ ] ole_methods_spec.rb
- [ ] ole_obj_help_spec.rb
- [ ] ole_put_methods_spec.rb
- [ ] setproperty_spec.rb

### library/win32ole/win32ole_event
- [ ] new_spec.rb
- [ ] on_event_spec.rb

### library/win32ole/win32ole_method
- [ ] dispid_spec.rb
- [ ] event_interface_spec.rb
- [ ] event_spec.rb
- [ ] helpcontext_spec.rb
- [ ] helpfile_spec.rb
- [ ] helpstring_spec.rb
- [ ] invkind_spec.rb
- [ ] invoke_kind_spec.rb
- [ ] name_spec.rb
- [ ] new_spec.rb
- [ ] offset_vtbl_spec.rb
- [ ] params_spec.rb
- [ ] return_type_detail_spec.rb
- [ ] return_type_spec.rb
- [ ] return_vtype_spec.rb
- [ ] size_opt_params_spec.rb
- [ ] size_params_spec.rb
- [ ] to_s_spec.rb
- [ ] visible_spec.rb

### library/win32ole/win32ole_param
- [ ] default_spec.rb
- [ ] input_spec.rb
- [ ] name_spec.rb
- [ ] ole_type_detail_spec.rb
- [ ] ole_type_spec.rb
- [ ] optional_spec.rb
- [ ] retval_spec.rb
- [ ] to_s_spec.rb

### library/win32ole/win32ole_type
- [ ] guid_spec.rb
- [ ] helpcontext_spec.rb
- [ ] helpfile_spec.rb
- [ ] helpstring_spec.rb
- [ ] major_version_spec.rb
- [ ] minor_version_spec.rb
- [ ] name_spec.rb
- [ ] new_spec.rb
- [ ] ole_classes_spec.rb
- [ ] ole_methods_spec.rb
- [ ] ole_type_spec.rb
- [ ] progid_spec.rb
- [ ] progids_spec.rb
- [ ] src_type_spec.rb
- [ ] to_s_spec.rb
- [ ] typekind_spec.rb
- [ ] typelibs_spec.rb
- [ ] variables_spec.rb
- [ ] visible_spec.rb

### library/win32ole/win32ole_variable
- [ ] name_spec.rb
- [ ] ole_type_detail_spec.rb
- [ ] ole_type_spec.rb
- [ ] to_s_spec.rb
- [ ] value_spec.rb
- [ ] variable_kind_spec.rb
- [ ] varkind_spec.rb
- [ ] visible_spec.rb

### library/yaml
- [ ] dump_spec.rb
- [ ] dump_stream_spec.rb
- [ ] load_file_spec.rb
- [ ] load_spec.rb
- [ ] load_stream_spec.rb
- [ ] parse_file_spec.rb
- [ ] parse_spec.rb
- [ ] to_yaml_spec.rb
- [ ] unsafe_load_spec.rb

### library/zlib
- [ ] adler32_spec.rb
- [ ] crc32_spec.rb
- [ ] crc_table_spec.rb

### library/zlib/deflate
- [ ] deflate_spec.rb
- [ ] params_spec.rb
- [ ] set_dictionary_spec.rb

### library/zlib
- [ ] deflate_spec.rb
- [ ] gunzip_spec.rb
- [ ] gzip_spec.rb

### library/zlib/gzipfile
- [ ] close_spec.rb
- [ ] closed_spec.rb
- [ ] comment_spec.rb
- [ ] orig_name_spec.rb

### library/zlib/gzipreader
- [ ] each_byte_spec.rb
- [ ] each_char_spec.rb
- [ ] each_line_spec.rb
- [ ] each_spec.rb
- [ ] eof_spec.rb
- [ ] getc_spec.rb
- [ ] gets_spec.rb
- [ ] mtime_spec.rb
- [ ] pos_spec.rb
- [ ] read_spec.rb
- [ ] readpartial_spec.rb
- [ ] rewind_spec.rb
- [ ] ungetbyte_spec.rb
- [ ] ungetc_spec.rb

### library/zlib/gzipwriter
- [ ] append_spec.rb
- [ ] mtime_spec.rb
- [ ] write_spec.rb

### library/zlib/inflate
- [ ] append_spec.rb
- [ ] finish_spec.rb
- [ ] inflate_spec.rb
- [ ] set_dictionary_spec.rb

### library/zlib
- [ ] inflate_spec.rb
- [ ] zlib_version_spec.rb

### library/zlib/zstream
- [ ] adler_spec.rb
- [ ] avail_in_spec.rb
- [ ] avail_out_spec.rb
- [ ] data_type_spec.rb
- [ ] flush_next_out_spec.rb

### optional/capi
- [ ] array_spec.rb
- [ ] basic_object_spec.rb
- [ ] bignum_spec.rb
- [ ] binding_spec.rb
- [ ] boolean_spec.rb
- [ ] class_spec.rb
- [ ] complex_spec.rb
- [ ] constants_spec.rb
- [ ] data_spec.rb
- [ ] debug_spec.rb
- [ ] digest_spec.rb
- [ ] encoding_spec.rb
- [ ] enumerator_spec.rb
- [ ] exception_spec.rb
- [ ] fiber_spec.rb
- [ ] file_spec.rb
- [ ] finalizer_spec.rb
- [ ] fixnum_spec.rb
- [ ] float_spec.rb
- [ ] gc_spec.rb
- [ ] globals_spec.rb
- [ ] hash_spec.rb
- [ ] integer_spec.rb
- [ ] io_spec.rb
- [ ] kernel_spec.rb
- [ ] language_spec.rb
- [ ] marshal_spec.rb
- [ ] module_spec.rb
- [ ] mutex_spec.rb
- [ ] numeric_spec.rb
- [ ] object_spec.rb
- [ ] proc_spec.rb
- [ ] range_spec.rb
- [ ] rational_spec.rb
- [ ] rbasic_spec.rb
- [ ] regexp_spec.rb
- [ ] set_spec.rb
- [ ] st_spec.rb
- [ ] string_spec.rb
- [ ] struct_spec.rb
- [ ] symbol_spec.rb
- [ ] thread_spec.rb
- [ ] time_spec.rb
- [ ] tracepoint_spec.rb
- [ ] typed_data_spec.rb
- [ ] util_spec.rb

### optional/thread_safety
- [ ] hash_spec.rb

### security
- [ ] cve_2010_1330_spec.rb
- [ ] cve_2011_4815_spec.rb
- [ ] cve_2013_4164_spec.rb
- [ ] cve_2018_16396_spec.rb
- [ ] cve_2018_6914_spec.rb
- [ ] cve_2018_8778_spec.rb
- [ ] cve_2018_8779_spec.rb
- [ ] cve_2018_8780_spec.rb
- [ ] cve_2019_8321_spec.rb
- [ ] cve_2019_8322_spec.rb
- [ ] cve_2019_8323_spec.rb
- [ ] cve_2019_8325_spec.rb
- [ ] cve_2020_10663_spec.rb
- [ ] cve_2024_49761_spec.rb
