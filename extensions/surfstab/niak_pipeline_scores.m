function [pipeline, opt] = niak_pipeline_scores(files_in, opt)
% Pseudocode of the pipeline:
% INPUTS
%
% FILES_IN  
%   (structure) with the following fields : 
%
%   DATA
%      (structure) with the following fields :
%
%      <SUBJECT>.<SESSION>.<RUN>
%         (string) a 3D+t fMRI dataset. The fields <SUBJECT>, <SESSION> 
%         and <RUN> can be any arbitrary string. Note that time series can 
%         be specified directly as variables in a .mat file. The file 
%         FILES_IN.ATOMS needs to be specified in that instance. 
%         The <SESSION> level can be skipped.
%   MASK
%       (string) path to the mask
%
%   PART
%       (string) path to the partition
%
% Check the options
%   - OPT is prety much a forward, no changes there
%   - Decide which files should be saved? Needs a separate thingy that is
%     either empty to save all or a structure to save only specific stuff.
%     Each file needs to be defined here with the default being yes.
%   - Maybe a folder that we want to store everything in
% OPT.FILES_OUT
%   STABILITY_MAPS
%     (boolean)
%   PARTITION_CORES
%     (boolean)
%   STABILITY_INTRA
%     (boolean)
%   STABILITY_INTRA
%     (boolean)
%   STABILITY_CONTRAST
%     (boolean)
%   PARTITION_THRESH
%     (boolean)
%   RMAP_PART
%     (boolean)
%   RMAP_CORES
%     (boolean)
%   DUAL_REGRESSION
%     (boolean)
%   EXTRA
%     (boolean)
%
% OPT.FLAG_VERBOSE (boolean, default true) turn on/off the verbose.
% OPT.FLAG_TARGET (boolean, default false)
%       If FILES_IN.PART has a second column, then this column is used as a binary mask to define 
%       a "target": clusters are defined based on the similarity of the connectivity profile 
%       in the target regions, rather than the similarity of time series.
%       If FILES_IN.PART has a third column, this is used as a parcellation to reduce the space 
%       before computing connectivity maps, which are then used to generate seed-based 
%       correlation maps (at full available resolution).
% OPT.FLAG_DEAL
%       If the partition supplied by the user does not have the appropriate
%       number of columns, this flag can force the brick to duplicate the
%       first column. This may be useful if you want to use the same mask
%       for the OPT.FLAG_TARGET flag as you use in the cluster partition.
%       Use with care.
%
% OPT.FLAG_FOCUS (boolean, default false)
%       If FILES_IN.PART has a two additional columns (three in total) then the
%       second column is treated as a binary mask of an ROI that should be
%       clustered and the third column is treated as a binary mask of a
%       reference region. The ROI will be clustered based on the similarity
%       of its connectivity profile with the prior partition in column 1 to
%       the connectivity profile of the reference.
% OPT.FLAG_TEST (boolean, default false) if the flag is true, the brick does not do anything
%      but update FILES_IN, FILES_OUT and OPT.

% FILES IN DEFAULTS
files_in = psom_struct_defaults(files_in, ...
           { 'data' , 'part' , 'mask' }, ...
           { NaN    , NaN    , NaN    });
% DEFAULTS
opt = psom_struct_defaults(opt,...
      { 'folder_out'      , 'files_out' , 'scores' , 'psom' , 'flag_test' },...
      { 'gb_niak_omitted' , struct      , struct   , struct , false       });
  
opt.psom = psom_struct_defaults(opt.psom,...
           { 'max_queued' , 'path_logs'             },...
           { 2            , [opt.folder_out filesep 'logs'] });

opt.files_out = psom_struct_defaults(opt.files_out,...
                { 'stability_maps' , 'partition_cores' , 'stability_intra' , 'stability_inter' , 'stability_contrast' , 'partition_thresh' , 'rmap_part', 'rmap_cores', 'dual_regression' , 'extra' , 'part_order' },...
                { true             , true              , true              , true              , true                 , true               , true       , true        , true              , true    , true         });

opt.scores = psom_struct_defaults(opt.scores, ...
             { 'type_center' , 'nb_iter' , 'folder_out' , 'thresh' , 'rand_seed' , 'nb_samps' , 'sampling' , 'flag_focus' , 'flag_target' , 'flag_deal' , 'flag_resample' , 'flag_verbose' , 'flag_test' } , ...
             { 'median'      , 1         , ''           ,  0.5      , []          , 100        , struct()  , false        , false         , false       , false           , true           , false       });

opt.scores.sampling = psom_struct_defaults(opt.scores.sampling, ...
                      { 'type' , 'opt'    }, ...
                      { 'CBB'  , struct() });

%% Turn the input structure into a cell array that will be used in the rest of
% the pipeline
list_subject = fieldnames(files_in.data);
% Get the number of subjects
nb_subject = length(list_subject);
[cell_fmri,labels] = niak_fmri2cell(files_in.data);
% Find out how many jobs we have to run
j_names = {labels.name};
j_number = length(j_names);
labels_subject = {labels.subject};
[path_f,name_f,ext] = niak_fileparts(cell_fmri{1});
fmri = niak_fmri2struct(cell_fmri,labels);

%% Sanity checks
files_out_set = false;
o_names = fieldnames(opt.files_out);
for o_id = 1:length(o_names)
    o_name = o_names{o_id};
    if opt.files_out.(o_name) && ~ischar(opt.files_out.(o_name))
        files_out_set = true;
    end
end

if opt.scores.flag_deal
    warning('OPT.SCORES.FLAG_DEAL is set to true. Check your partition to make sure it does what you expect.');
end

if strcmp('gb_niak_omitted' , opt.folder_out) && files_out_set
    error(['Please specify either OPT.FOLDER_OUT, set unwanted files to '...
           '''false'' or specify their output path individually']);
end

% Check if the fmri and partition data have the same dimensions
[ah, av] = niak_read_vol(files_in.part);
[fh, fv] = niak_read_vol(cell_fmri{1});
if ~isequal(ah.info.dimensions, fh.info.dimesions) || ~isequal(ah.info.voxel_size, fh.info.voxel_size)
    % Either the dimensions of the files or the voxels dimensions or both do not match
    % We need to resample the template to match the functional data
    warning(['Either the dimensions, the voxel size or both are different ',...
            'for the template and the functional data. I will resample the template!\n',...
            '    template dimensions: %s\n',...
            '    template voxel size: %s\n',...
            '    functional dimensions: %s\n',...
            '    functional voxel size: %s\n'],num2str(ah.info.dimensions), num2str(ah.info.voxel_size),num2str(fh.info.dimesions), num2str(fh.info.voxel_size));
    opt.template_resample = true;
end

% Check the same thing for the mask
[mh, mv] = niak_read_vol(files_in.mask);
if ~isequal(mh.info.dimensions, fh.info.dimesions) || ~isequal(mh.info.voxel_size, fh.info.voxel_size)
    % Either the dimensions of the files or the voxels dimensions or both do not match
    % We need to resample the mask to match the functional data
    warning(['Either the dimensions, the voxel size or both are different ',...
            'for the mask and the functional data. I will resample the mask!\n',...
            '    mask dimensions: %s\n',...
            '    mask voxel size: %s\n',...
            '    functional dimensions: %s\n',...
            '    functional voxel size: %s\n'],num2str(mh.info.dimensions), num2str(mh.info.voxel_size),num2str(fh.info.dimesions), num2str(fh.info.voxel_size));
    opt.mask_resample = true;
end

%% Begin the pipeline
pipeline = struct;

% See if we need to add the jobs to resample the template and the mask
if ~same_res(cell_fmri{1}, files_in.part, 'partition')
    % We need to resample the partition
    clear job_in job_out job_opt
    job_in.source      = files_in.part;
    [path_f,name_f,ext_f] = niak_fileparts(files_in.part);
    job_in.target      = cell_fmri{1};
    job_out            = [opt.folder_out 'template_partition' ext_f];
    job_opt.interpolation    = 'nearest_neighbour';
    pipeline = psom_add_job(pipeline,'scores_resample_part','niak_brick_resample_vol',job_in,job_out,job_opt);
end

if ~same_res(cell_fmri{1}, files_in.mask, 'mask')
    % We need to resample the partition
    clear job_in job_out job_opt
    job_in.source      = files_in.mask;
    [path_f,name_f,ext_f] = niak_fileparts(files_in.mask);
    job_in.target      = cell_fmri{1};
    job_out            = [opt.folder_out 'mask' ext_f];
    job_opt.interpolation    = 'nearest_neighbour';
    pipeline = psom_add_job(pipeline,'scores_resample_mask','niak_brick_resample_vol',job_in,job_out,job_opt);
end

% Run the jobs
for j_id = 1:j_number
    % Get the name of the subject
    s_name = j_names{j_id};
    j_name = sprintf('scores_%s', j_names{j_id});
    s_in.fmri = cell_fmri(j_id);
    if ~same_res(cell_fmri{1}, files_in.part, 'partition')
        s_in.part = pipeline.scores_resample_part.files_out;
    else
        s_in.part = files_in.part;
    end

    s_in.mask = files_in.mask;
    s_out = struct;
    % Set the paths for the requested output files
    for out_id = 1:length(o_names)
        out_name = o_names{out_id};
        if opt.files_out.(out_name) && ~ischar(opt.files_out.(out_name))
            if strcmp(out_name, 'extra')
                s_out.(out_name) = [opt.folder_out filesep out_name filesep sprintf('%s_%s.mat',s_name, out_name)];
            elseif strcmp(out_name, 'part_order')
                fprintf('I am here, what now?\n');
                s_out.(out_name) = [opt.folder_out filesep out_name filesep sprintf('%s_%s.csv',s_name, out_name)];
            else
                s_out.(out_name) = [opt.folder_out filesep out_name filesep sprintf('%s_%s%s',s_name, out_name, ext)];
            end 
        elseif ~opt.files_out.(out_name)
            s_out.(out_name) = 'gb_niak_omitted';
            continue
        elseif ischar(opt.files_out.(out_name))
            error('OPT.FILES_OUT can only have boolean values but not %s',class(opt.files_out.(out_name)));
        end
        if ~isdir([opt.folder_out filesep out_name])
                psom_mkdir([opt.folder_out filesep out_name]);
        end
    end
    s_opt = opt.scores;
    pipeline = psom_add_job(pipeline, j_name, 'niak_brick_scores_fmri',...
                            s_in, s_out, s_opt);
end

%% Run the pipeline 
if ~opt.flag_test
    psom_run_pipeline(pipeline, opt.psom);
end

function test = same_res(ref_file, test_file, test_name)
    % Test if both files have the same voxel dimensions and 
    % dimensions
    [rh, ~] = niak_read_vol(ref_file);
    [th, ~] = niak_read_vol(test_file);
    rdim = rh.info.dimensions(1:3);
    tdim = th.info.dimensions(1:3);
    rvox = rh.info.voxel_size;
    tvox = rh.info.voxel_size;
    if ~isequal(rdim, tdim) || ~isequal(rvox, tvox)
        % Either the dimensions of the files or the voxels dimensions or both do not match
        warning(['Either the dimensions, the voxel size or both are different ',...
                'for the %s and the functional data. I will resample the %s!\n',...
                '    %s dimensions: %s\n',...
                '    %s voxel size: %s\n',...
                '    functional dimensions: %s\n',...
                '    functional voxel size: %s\n'],test_name, test_name, test_name, num2str(tdim), test_name, num2str(tvox),num2str(rdim), num2str(rvox));
        test = false;
    else
        test = true;
    end