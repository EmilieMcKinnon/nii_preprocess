function dwi_norm(dwi, lesion, isTrace, force)
%Normalize diffusion weighted image and associated lesion
% dwi : filename of diffusion image
% lesion : map of brain injury
% istrace : if dwi is single volume, decide whether image is B=0 or Trace
% force : recompute even if mat file exists
%Given a lesion SUBJ.voi and DWI image SUBJ*.nii, normalize the lesion
%  using the B0 image from the scan. The file SUBJ*.nii is assumed to have
%  two volumes - a trace image (which shows the lesion) and a B0 image
%  (where hyperacute injuries are not visible). The B0 is used for the
%  transform, and the transforms applied to the lesion, B0 and trace
% Lesions were manually drawn on the DWI trace images using MRIcron.
% SPM12?s ?old normalization? method was used to compute the non-linear
% transform of the DWI B0 image to match the SPM ?EPI? template.
% This transform was then applied to the lesion map. Note that the DWI trace
% and B0 images are derived from the same sequence, but hyper-acute injuries
% are typically not visible on the B0 image, allowing effective
% normalization (Mah et al., 2014). The lesion maps were resliced using
% linear interpolation to 1mm isotropic and binarized using a 50%
% probability threshold.
%Mah YH, Jager R, Kennard C, Husain M, Nachev P. (2014) A new method for
%  automated high-dimensional lesion segmentation evaluated in vascular
%  injury and applied to the human occipital lobe. Cortex. 56:51-63.

if ~exist('dwi','var')
 dwi = spm_select(inf,'^.*\.(gz|nii)$','Select DWI image');
 if isempty(dwi), return; end;
 isGui = true;
else
    isGui = false;
end;
if ~exist('lesion','var')
 %lesion = spm_select(inf,'^.*\.(gz|nii|voi)$','Select lesion image');
 lesion = spm_select(inf,'^.*\.(voi)$','Select lesion image');
 if isempty(lesion), return; end;
end;
if ~exist('force','var'), force = false; end;
if isempty(which('spm')) || ~strcmp(spm('Ver'),'SPM12'), error('SPM12 required'); end;
if isempty(spm_figure('FindWin','Graphics')), spm fmri; end; %launch SPM if it is not running
dwi = unGzSub(dwi); %.nii.gz -> .nii
[p,n] = fileparts(lesion);
matName = fullfile(p, [n, '.mat']);
if exist(matName,'file') && ~force, fprintf('%s skipped since file exists %s\n', mfilename, matName); return; end;
hdr = spm_vol(dwi);
[pth nm ext] = spm_fileparts(hdr(1).fname);
trace = [];
if numel(hdr) > 1 %if two volumes, determine which is B=0 and which is trace
   img = spm_read_vols(hdr);
   img1 = img(:,:,:,1);
   img2 = img(:,:,:,2);
   if mean(img1(:)) < mean(img2(:))
    img2 = img(:,:,:,1);
    img1 = img(:,:,:,2);
   end
   hdr = hdr(1);
   dwi = fullfile(pth, ['b0_' nm ext]);
   trace = fullfile(pth, ['tr_' nm ext]);
   hdr.fname = dwi;
   spm_write_vol(hdr,img1);
   hdr.fname = trace;
   spm_write_vol(hdr,img2);
else
    if ~exist('isTrace','var') || isempty(isTrace)
        b0Str = 'B0 (T2, CSF bright)';
        traceStr = 'Trace (CSF dark)';
        [~,nam] = fileparts(dwi);      
        button = questdlg(sprintf('What is the modality of "%s"?', nam),'Select modality',traceStr,b0Str,traceStr);
        isTrace = strcmpi(button, traceStr);
    end
    trace = [];
end

lesion = unGzSub(lesion); %.voi -> .nii
reg = 0.3; 
fprintf('Regularization = %.2f (1 for T1 scans, ~0.3 for very distorted EPI-based DWI)\n', reg);
if isempty(trace)
    if exist('isTrace','var') && isTrace
        p = fileparts(which(mfilename));
        template = fullfile(p,'mean_TRACE_of_381_8mmFWHM.nii');
    else
        template  = fullfile(spm('Dir'),'toolbox','OldNorm','EPI.nii');
    end
    if ~exist(template,'file'), error('Can not find %s',template); end;
    [pth nm ext] = spm_fileparts(hdr(1).fname);
    %return; %to report broken files!
    if isTrace
        fprintf('%s expect 2 images (B0 and Trace). ASSUMING TRACE!',dwi);
        trace = fullfile(pth, ['tr_' nm ext]);
        copyfile(dwi,trace);
        dwi = trace;
        nii_setOrigin12({dwi,lesion}, 3, false); %T2 with yoked Lesion
        oldNormSub( {dwi,lesion}, template, 0, reg);
        bo = [];
    else
        fprintf('%s expect 2 images (B0 and Trace). ASSUMING B0!',dwi);
        b0 = fullfile(pth, ['b0_' nm ext]);
        copyfile(dwi,b0);
        dwi = b0;
        nii_setOrigin12({dwi,lesion}, 3, false); %T2 with yoked Lesion
        oldNormSub( {dwi,lesion}, template, 0, reg);
        trace = [];
    end;
else
    template  = fullfile(spm('Dir'),'toolbox','OldNorm','EPI.nii');
    nii_setOrigin12({dwi,lesion,trace}, 3, false); %T2 with yoked Lesion
    oldNormSub( {dwi,lesion,trace}, template, 0, reg);
end;
lesion = prefixSub('w', lesion);
nii_nii2mat(lesion, 'lesion', matName); %1
%save DWI images
if isempty(trace)
    b0 = prefixSub('w', b0);
    if exist(b0,'file')
        hdr = spm_vol(b0);
        img = spm_read_vols(hdr);
        stat = [];
        stat.b0.hdr = hdr;
        stat.b0.dat = img;
        old = load(matName);
        stat = nii_mergestruct(stat,old); %#ok<NASGU>
        save(matName,'-struct', 'stat');
    end
	nii_mat2ortho(matName,'dwi_norm.ps');
	return;
end;
trace = prefixSub('w', trace);
if ~exist(trace,'file'), return; end;
hdr = spm_vol(trace);
img = spm_read_vols(hdr);
stat = [];
stat.DWI.hdr = hdr;
stat.DWI.dat = img;
old = load(matName);
stat = nii_mergestruct(stat,old); %#ok<NASGU>
save(matName,'-struct', 'stat');
nii_mat2ortho(matName,'dwi_norm.ps');
%normDwiSub()

function nam = prefixSub(pre, nam)
if isempty(nam), return; end;
[p, n, x] = spm_fileparts(nam);
nam = fullfile(p, [pre, n, x]);
%end prefixSub()

function oldNormSub(src, tar, smoref, reg, interp)
%coregister T2 to match T1 image, apply to lesion
if isempty(src) || isempty(tar), return; end;
if ~exist('smoref','var'), smoref = 0; end;
if ~exist('reg','var'), reg = 1; end;
if ~exist('interp','var'), interp = 1; end;
fprintf('Normalizing %s to appear like %s\n', src{1}, tar);
matlabbatch{1}.spm.tools.oldnorm.estwrite.subj.source = src(1);
matlabbatch{1}.spm.tools.oldnorm.estwrite.subj.wtsrc = '';
matlabbatch{1}.spm.tools.oldnorm.estwrite.subj.resample = src(:);
matlabbatch{1}.spm.tools.oldnorm.estwrite.eoptions.template = {tar};
matlabbatch{1}.spm.tools.oldnorm.estwrite.eoptions.weight = '';
matlabbatch{1}.spm.tools.oldnorm.estwrite.eoptions.smosrc = 8;
matlabbatch{1}.spm.tools.oldnorm.estwrite.eoptions.smoref = smoref; % <-- !!!
matlabbatch{1}.spm.tools.oldnorm.estwrite.eoptions.regtype = 'mni';
matlabbatch{1}.spm.tools.oldnorm.estwrite.eoptions.cutoff = 25;
matlabbatch{1}.spm.tools.oldnorm.estwrite.eoptions.nits = 16;
matlabbatch{1}.spm.tools.oldnorm.estwrite.eoptions.reg = reg;
matlabbatch{1}.spm.tools.oldnorm.estwrite.roptions.preserve = 0;
%matlabbatch{1}.spm.tools.oldnorm.estwrite.roptions.bb = [nan nan nan; nan nan nan];%[-78 -112 -70; 78 76 85];
matlabbatch{1}.spm.tools.oldnorm.estwrite.roptions.bb = [-78 -112 -70; 78 76 85];
matlabbatch{1}.spm.tools.oldnorm.estwrite.roptions.vox = [1 1 1];
matlabbatch{1}.spm.tools.oldnorm.estwrite.roptions.interp = interp;
matlabbatch{1}.spm.tools.oldnorm.estwrite.roptions.wrap = [0 0 0];
matlabbatch{1}.spm.tools.oldnorm.estwrite.roptions.prefix = 'w';
spm_jobman('run',matlabbatch);
%end oldNormSub()

function fnm = unGzSub (fnm)
[pth,nam,ext] = spm_fileparts(fnm);
if strcmpi(ext,'.gz') %.nii.gz
    fnm = char(gunzip(fnm));
elseif strcmpi(ext,'.voi') %.voi ->
    onam = char(gunzip(fnm));
    fnm = fullfile(pth, ['LESION_' nam '.nii']);
    movefile(onam,fnm);
end;
%end unGzSub()