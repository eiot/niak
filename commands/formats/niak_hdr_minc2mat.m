function [mat] = niak_hdr_minc2mat(direction_cosine,step,start)

% Convert a "voxel-to-world" coordinates affine transformation from the 
% cosines/start/step representation used in minc headers to the standard
% 4*4 matrix array (y=M*x+T).
%
% SYNTAX:
% [MAT] = NIAK_HDR_MINC2MAT(DIRECTION_COSINE,STEP,START)
% 
% INPUT:
% DIRECTION_COSINES (array 3*3) gives you the direction assigned to the
%           respective dimensions of the voxel array.
%
% START (vector 3*1) the starting value of each voxel dimension along the
%       DIRECTION_COSINES vector.
%
% STEP  (vector 3*1) the step made at each voxel dimension along the
%       DIRECTION_COSINES vector.
%
% OUTPUTS:
% MAT   (4*4 array) An affine transformation, usually seen as a
%           "voxel-to-world" space transform.
% 
% COMMENTS:
% This function is based on the description of MINC2 system of coordinates
% that can be found at :
% http://www.bic.mni.mcgill.ca/software/minc/minc2_format/node4.html
%
% SEE ALSO:
% NIAK_READ_HDR_MINC, NIAK_WRITE_MINC
%
% Copyright (c) Pierre Bellec, McConnel Brain Imaging Center, Montreal 
% Neurological Institute, McGill University, Montreal, Canada, 2008.
% Maintainer : pbellec@bic.mni.mcgill.ca
% See licensing information in the code.
% Keywords : medical imaging, I/O, affine transformation

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

mat = eye(4);
mat(1:3,1:3) = direction_cosine * (diag(step));
mat(1:3,4) = direction_cosine * start;