function [files_out,opt] = niak_brick_fmri_design(files_in,opt)

% SYNTAX:
% [FILES_OUT,OPT] = NIAK_BRICK_FMRI_DESIGN(FILES_IN,OPT)
%
% _________________________________________________________________________
% INPUTS
%
%  * FILES_IN  
%       (structure) with the following field :
%
%       FMRI 
%           (string) the name of a file containing an fMRI dataset. 
%     
%
% _________________________________________________________________________
% OPT   
%     (structure) with the following fields.
%     Note that if a field is omitted, it will be set to a default
%     value if possible, or will issue an error otherwise.
%
%
%     EVENTS 
%           (matrix, default [1 0]) rows are events and columns are:
%           1. id - an integer from 1:(number of events) to identify event type;
%           2. times - start of event, synchronised with frame and slice times;
%           3. durations (optional - default is 0) - duration of event;
%           4. heights (optional - default is 1) - height of response for event.
%           For each event type, the response is a box function starting at the 
%           event times, with the specified durations and heights, convolved with 
%           the hemodynamic response function (see below). If the duration is zero, 
%           the response is the hemodynamic response function whose integral is 
%           the specified height - useful for `instantaneous' stimuli such as visual 
%           stimuli. The response is then subsampled at the appropriate frame and 
%           slice times to create a design matrix for each slice, whose columns 
%           correspond to the event id number. EVENT_TIMES=[] will ignore event 
%           times and just use the stimulus design matrix S (see next). 
%
%     SLICE_TIMES 
%           (row vector, default 0) relative slice acquisition times i.e. 
%           absolute acquisition time of a slice is FRAME_TIMES+SLICE_TIMES
%
%     SPATIAL_AV
%           (default [] and NB_TRENDS_SPATIAL = 0)
%           colum vector of the spatial average time courses.
%
%     CONFOUNDS 
%           (matrix, default [] i.e. no confounds)
%           A matrix or array of extra columns for the design matrix
%           that are not convolved with the HRF, e.g. movement artifacts. 
%           If a matrix, the same columns are used for every slice; if an array,
%           the first two dimensions are the matrix, the third is the slice.
%           For functional connectivity with a single voxel, use
%           FMRI_INTERP to resample the reference data at different slice 
%           times, or apply NIAK_BRICK_SLICE_TIMING to the fMRI data as a
%           preprocessing.
%
%     EXCLUDE 
%           (vector, default []) 
%           A list of frames that should be excluded from the
%           analysis. This must be used with Siemens EPI scans to remove the
%           first few frames, which do not represent steady-state images.
%           If OPT.NUMLAGS=1, the excluded frames can be arbitrary, 
%           otherwise they should be from the beginning and/or end.
%
%     NB_TRENDS_SPATIAL 
%           (scalar, default 0 will remove no spatial trends) 
%           order of the polynomial in the spatial average (SPATIAL_AV)  
%           weighted by first non-excluded frame; 
%          
%     NB_TRENDS_TEMPORAL 
%           (scalar, default 0)
%           number of cubic spline temporal trends to be removed per 6 
%           minutes of scanner time. 
%           Temporal  trends are modeled by cubic splines, so for a 6 
%           minute run, N_TEMPORAL<=3 will model a polynomial trend of 
%           degree N_TEMPORAL in frame times, and N_TEMPORAL>3 will add 
%           (N_TEMPORAL-3) equally spaced knots.
%           N_TEMPORAL=0 will model just the constant level and no 
%           temporal trends.
%           N_TEMPORAL=-1 will not remove anything, in which case the design matrix 
%           is completely determined by X_CACHE.X.
%
%     NUM_HRF_BASES 
%           (row vector; default [1; ... ;1]) 
%           number of basis functions for the hrf for each response, 
%           either 1 or 2 at the moment. At least one basis functions is 
%           needed to estimate the magnitude, but two basis functions are 
%           needed to estimate the delay.
%
%     BASIS_TYPE 
%           (string, 'spectral') 
%           basis functions for the hrf used for delay estimation, or 
%           whenever NUM_HRF_BASES = 2. 
%           These are convolved with the stimulus to give the responses in 
%           Dim 3 of X_CACHE.X:
%           'taylor' - use hrf and its first derivative (components 1&2)
%           'spectral' - use first two spectral bases (components 3&4 of 
%           Dim 3).
%           Ignored if NUM_HRF_BASES = 1, in which case it always uses 
%           component 1, i.e. the hrf is convolved with the stimulus.
%
%     FOLDER_OUT 
%           (string, default: path of FILES_IN) 
%           If present, all default outputs will be created in the folder 
%           FOLDER_OUT. The folder needs to be created beforehand.
%
%     FLAG_VERBOSE 
%           (boolean, default 1) 
%           if the flag is 1, then the function prints some infos during 
%           the processing.
%
%     FLAG_TEST 
%           (boolean, default 0) 
%           if FLAG_TEST equals 1, the brick does not do anything but 
%           update the default values in FILES_IN, FILES_OUT and OPT.
%
%
% _________________________________________________________________________
% OUTPUTS
%
%  * FILES_OUT 
%       (structure) with the following field. Note that if
%       a field is an empty string, a default value will be used to
%       name the outputs. If a field is omitted, the output won't be
%       saved at all (this is equivalent to setting up the output file
%       names to 'gb_niak_omitted').
%
%       DESIGN 
%           (string) a MAT file containing the variable X_CACHE and MATRIX_X. 
%           X_CACHE describes the covariates of the model.
%           See the help of FMRIDESIGN in the fMRIstat toolbox and
%           http://www.math.mcgill.ca/keith/fmristat/#making for an 
%           example.
%           MATRIX_X is the full design matrix, resulting from concatenating 
%           X_CACHE with the temporal, spatial trends as well as additinal 
%           confounds.
%
%      The structure OPT is updated with default values. 
%      If OPT.FLAG_TEST == 0, the specified outputs are written.
%
% _________________________________________________________________________
% COMMENTS
%
% This function is a NIAKIFIED port of a part of the FMRILM function of the
% fMRIstat project. The original license of fMRIstat was : 
%
%############################################################################
% COPYRIGHT:   Copyright 2002 K.J. Worsley
%              Department of Mathematics and Statistics,
%              McConnell Brain Imaging Center, 
%              Montreal Neurological Institute,
%              McGill University, Montreal, Quebec, Canada. 
%              worsley@math.mcgill.ca, liao@math.mcgill.ca
%
%              Permission to use, copy, modify, and distribute this
%              software and its documentation for any purpose and without
%              fee is hereby granted, provided that the above copyright
%              notice appear in all copies.  The author and McGill University
%              make no representations about the suitability of this
%              software for any purpose.  It is provided "as is" without
%              express or implied warranty.
%##########################################################################
%
% Copyright (c) Felix Carbonell, Montreal Neurological Institute, 2009.
%               Pierre Bellec, McConnell Brain Imaging Center, 2009.
% Maintainers : felix.carbonell@mail.mcgill.ca, pbellec@bic.mni.mcgill.ca
% See licensing information in the code.
% Keywords : fMRIstat, linear model

% Permission is hereby granted, free of charge, to any person obtaining a copy
% of this software and associated documentation files (the "Software"), to deal
% in the Software without restriction, including without limitation the rights
% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
% copies of the Software, and to permit persons to whom the Software is
% furnished to do so, subject to the following conditions:
%
% The above copyright notice and this permission notice shall be included in
% all copies or substantial portions of the Software.
%
% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
% THE SOFTWARE.


niak_gb_vars

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Setting up default arguments %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% SYNTAX
if ~exist('files_in','var')|~exist('opt','var')
    error('SYNTAX: [FILES_OUT,OPT] = NIAK_BRICK_FMRI_DESIGN(FILES_IN,OPT).\n Type ''help niak_brick_fmri_design'' for more info.')
end

%% FILES_IN
gb_name_structure = 'files_in';
gb_list_fields = {'fmri'};
gb_list_defaults = {NaN};
niak_set_defaults

if ~ischar(files_in.fmri)
    error('niak_brick_fmri_design: FILES_IN.FMRI should be a string');
end

%% OPTIONS
gb_name_structure = 'opt';
gb_list_fields = {'events','slice_times','spatial_av','confounds','exclude','nb_trends_spatial','nb_trends_temporal','num_hrf_bases','basis_type','flag_test','folder_out','flag_verbose'};
gb_list_defaults = {[1 0],NaN,[],[],[],0,3,[],'spectral',0,'',1};
niak_set_defaults


if (nb_trends_spatial>=1) && isempty(spatial_av)
    error('Please provide a non empty value for SPATIAL_AV.\n Type ''help niak_brick_fmri_design'' for more info.')
end


%% FILES_OUT
gb_name_structure = 'files_out';
gb_list_fields = {'design'};
gb_list_defaults = {'gb_niak_omitted'};
niak_set_defaults

%% Parsing base names
[path_f,name_f,ext_f] = fileparts(files_in.fmri);

if isempty(path_f)
    path_f = '.';
end

if strcmp(ext_f,gb_niak_zip_ext)
    [tmp,name_f] = fileparts(name_f);
    flag_zip = 1;
else
    flag_zip = 0;
end

if isempty(opt.folder_out)
    folder_f = path_f;
else
    folder_f = opt.folder_out;
end

files_out.design = cat(2,folder_f,filesep,name_f,'_design.mat');

%% Input file
if flag_zip
    file_input = niak_file_tmp(cat(2,'_func.mnc',gb_niak_zip_ext));
    instr_cp = cat(2,'cp ',files_in.fmri,' ',file_input);
    system(instr_cp);
    instr_unzip = cat(2,gb_niak_unzip,' ',file_input);
    system(instr_unzip);
    file_input = file_input(1:end-length(gb_niak_zip_ext));
else
    file_input = files_in.fmri;
end


%% Open file_input:
hdr = niak_read_vol(file_input);

%% Image dimensions
numslices = hdr.info.dimensions(3);
numframes = hdr.info.dimensions(4);

%% Creates temporal and spatial trends:
opt_trends.nb_trends_temporal = opt.nb_trends_temporal;
opt_trends.nb_trends_spatial = opt.nb_trends_spatial;
opt_trends.exclude = opt.exclude;
opt_trends.tr = hdr.info.tr;
opt_trends.confounds = opt.confounds;
opt_trends.spatial_av = opt.spatial_av;
opt_trends.nb_slices = numslices;
opt_trends.nb_frames = numframes;
trend = niak_make_trends(opt_trends); 
clear opt.trends

%% Creates x_cache
opt_cache.frame_times = (0:(numframes-1))*hdr.info.tr;
opt_cache.slice_times = opt.slice_times;
opt_cache.events = opt.events;
x_cache = niak_fmridesign(opt_cache);
clear opt_cache

if ~isempty(x_cache.x)
    nb_response = size(x_cache.x,2);
else
    nb_response = 0;
end
if isempty(opt.num_hrf_bases)
    opt.num_hrf_bases = ones([nb_response 1]);
end

%% Creates matrix_x
opt_x.exclude = opt.exclude;
opt_x.num_hrf_bases = opt.num_hrf_bases;
opt_x.basis_type = opt.basis_type;
matrix_x = niak_full_design(x_cache,trend,opt_x);
clear opt_x;

if ~strcmp(files_out.design,'gb_niak_omitted');
    save(files_out.design,'x_cache','matrix_x');
end

%% Deleting temporary files
if flag_zip
    delete(file_input);
end