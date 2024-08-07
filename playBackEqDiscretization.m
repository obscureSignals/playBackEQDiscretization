close all 
clear 
clc 

% RIAA playback time constants
T0 = 318e-6; % bass boost
T1 = 75e-6; % treble roll-off
T2 = 3180e-6; % bass shelf

b0 = [0 1/T1 1/(T1*T0)];  % continuous time numerator 
a0 = [1 (T1+T2)/(T1*T2) 1/(T1*T2)]; % continuous time denominator 

%liveScript:  or enter your own s-domain transfer function? Interface like
%plugin? 

sdtf = tf(b0, a0); % make continuous transer function object
bOrderOriginal = length(b0)-1; % order of s-domain numerator 
aOrderOriginal = length(a0)-1; % order of s-domain denominator 

liveScript: load  your own file? we would still run the impulse for the
%plots

fs = 48e3; % original sample rate 
T = 1/fs; % original sample period

f = (0:fs/2-1)'; % 1Hz resolution regardless of sample rate 
radPerSec = (2*pi*f); % rad/sample array
radPerSample = radPerSec/fs; % rad/sample array

duration = 0.5; % length of time domain response in seconds 

t = 0:T:duration-T; % time array for IR plot

H0 = freqs(b0,a0,radPerSec); % complex freq response of s-domain transfer function
[h0, ~] = impulse(sdtf,t); % continues time IR
h0 = h0/fs;

% input impulse
x = zeros(fs*duration,1); 
x(1) = 1;

%%%%%%%%%%%%%%%% Setup Oversampling %%%%%%%%%%%%%%%%%%%
overSampleExp = 5; % oversamplig exponent - upsample rate will be 2^overSampleExp*fs
fsUp = fs*2^overSampleExp; % upsample rate
Tup = 1/fsUp; % upsample period
[upFilts, downFilts] = getOverSamplingFilters(overSampleExp); % get anti-alias/image filters
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Choose your transform. Options are
% 0: Zero-Order Hold
% 1: Triangle Approximation
% 2: Impulse Invariant 
% 3: Bilinear
% 4: Zero-Pole Matching
% 5: Curve Fitting (Complex)
% 6: Curve Fitting (Magnitude Only) 
% 7: Nyquist Band Transform

transformNum = 3;

%%%%%%%%%%%%%%%%%% Transforms %%%%%%%%%%%%%%%%%%%%
switch transformNum
    case 0
        tic
        zdtf = c2d(sdtf,Tup,'zoh');
        procTime = toc;
        transformName = 'Zero-Order Hold';
        % discrete time coefficients 
        b1 = zdtf.Numerator{1}; 
        a1 = zdtf.Denominator{1};       
    case 1
        tic
        zdtf = c2d(sdtf,Tup,'foh');
        procTime = toc;
        transformName = 'Triangle Approximation';
        % discrete time coefficients 
        b1 = zdtf.Numerator{1}; 
        a1 = zdtf.Denominator{1};
    case 2
        Tup = 1/fsUp; % sample period at upsample rate
        tic
        zdtf = c2d(sdtf,Tup,'impulse');
        procTime = toc;
        transformName = 'Impulse Invariant';
        % discrete time coefficients 
        b1 = zdtf.Numerator{1}; 
        a1 = zdtf.Denominator{1};
    case 3
        tic
        zdtf = c2d(sdtf,Tup,'tustin');
        procTime = toc;
        transformName = 'Bilinear Transform';
        % discrete time coefficients 
        b1 = zdtf.Numerator{1}; 
        a1 = zdtf.Denominator{1};    
    case 4
        tic
        zdtf = c2d(sdtf,Tup,'matched');
        procTime = toc;
        transformName = 'Zero-Pole Matching';
        % discrete time coefficients 
        b1 = zdtf.Numerator{1}; 
        a1 = zdtf.Denominator{1};    
    case 5
        fUp = (0:fsUp/2-1)'; % 1Hz resolution regardless of sample rate 
        radPerSecUp = (2*pi*fUp); % rad/sample array
        radPerSampleUp = radPerSecUp/fsUp; % rad/sample array
        H0Up = freqs(b0,a0,radPerSecUp); % complex freq response of s-domain transfer function
        wts = getBkWts((0:fsUp/2-1)');
        tic
        [b1,a1] = invfreqz(H0Up,radPerSampleUp,bOrderOriginal,aOrderOriginal,wts,1e2,0.001);
        procTime = toc;
        transformName = 'Complex Error Minimization';
    case 6
        Nfft = fs;
        tic
        [b1,a1] = invFreqzMagOnly(b0,a0,fsUp,Nfft,bOrderOriginal,aOrderOriginal);
        procTime = toc;
        transformName = 'Magnitude Error Minimization';
    case 7
        Nfft = fs;
        [b1,a1,procTime] = nyquistBandTransform(b0,a0,fsUp,aOrderOriginal);
        transformName = 'Nyquist Band Transform';

end 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%% Begin Processing %%%%%%%%%%%%%%%%

% upsample
for stage = 1:overSampleExp
    x = upFilts{stage}(x); 
end

y = filter(b1,a1,x); % filter 
yIR = x; % maintain an unfiltered, but oversampled impulse for calculating delay

% downsample
for stage = overSampleExp:-1:1
    y = downFilts{stage}(y); 
    yIR = downFilts{stage}(yIR); 
end

%%%%%%%%%%%%%%%%%%%%%%
delay = grpdelay(yIR); % group delay at all freq bins
delay = delay(1); % just group delay of first bin - TODO: why do you lose linear phase at higher overSampleExps
delayInt = round(delay); % for offsetting impulse in plot

[H1, ~] = freqz(y,1,fs/2,fs);  % complex freq response of discrete system

h0 = [zeros(delayInt,1); h0(1:end-delayInt,1)]; % offset continues time IR to delay of discrete system

% create phase compensation array to undo linear phase shift in plot
phaseComp = ((f/fs)*2*pi)*delay; 

H1ang = unwrap(angle(H1))+phaseComp; % add phase compensation

testFreq = 20e3;
testIdx = find(f>=testFreq,1);
magError = abs(mag2db(abs(H0(testIdx))/abs(H1(testIdx))));
phaseError = abs(rad2deg(angle(H0(testIdx))-H1ang(testIdx)));

normFact = max(abs(h0)); % normalization factor for time domain 

% normalize time domain signals 
h0 = h0/normFact;
y = y/normFact;

%%%%%%%%%%%%%%%%%%%%% Error calcs %%%%%%%%%%%%%%%%%%%%%
% find frequency index closest to 20 Hz 
twentyHzIdx = find(f >= 20,1); % this should always be equal to 21
% find frequency index closest to 20 kHz
twentyKhzIdx = find(f >= 20e3,1); % this should always be equal to 20001
H0BandLim = H0(twentyHzIdx:twentyKhzIdx); % H0 bandlimited 0-20kHz
H1BandLim = H1(twentyHzIdx:twentyKhzIdx); % H1 bandlimited 0-20kHz
H1angBandLim = H1ang(twentyHzIdx:twentyKhzIdx);
fBandLim = f(twentyHzIdx:twentyKhzIdx);

% find time index closest to 0.01 seconds
timeIdx = find(t == 0.01,1); 
posIdxs = [abs(0.01-t(timeIdx)),abs(0.01-t(timeIdx-1))];
[~, IdxTemp] = min(posIdxs);
timeIdx = timeIdx-(IdxTemp-1);

% time
timeRMSE = sqrt(mean((h0(1:timeIdx)-y(1:timeIdx)).^2)); % TODO: Should this be calculated over less time? Rn it dpeends on duration. 

% magnitude
sqMagError = (mag2db(abs(H0BandLim)./abs(H1BandLim))).^2;
weights = getBkWts(fBandLim);
sqMagErrorWeighted = weights.*sqMagError;
rootMeanSqMagErrorWeighted = sqrt(sum(sqMagErrorWeighted)/sum(weights));

% phase
sqPhaseError = (rad2deg(angle(H0BandLim))-rad2deg(H1angBandLim)).^2;
sqPhaseErrorWeighted = weights.*sqPhaseError;
rootMeanSqPhaseErrorWeighted = sqrt(sum(sqPhaseErrorWeighted)/sum(weights));
    
% root mean squared euclidean distance in the complex plane
H1BandLimPhaseComp = abs(H1BandLim).*exp(1j*H1angBandLim); 
sqComplexError = abs(H0BandLim-H1BandLimPhaseComp).^2;
sqComplexErrorWeighted = weights.*sqComplexError;
rootMeanSqComplexErrorWeighted = sqrt(sum(sqComplexErrorWeighted)/sum(weights));

%%%%%%%%%%%%%%%%%%%%% plots %%%%%%%%%%%%%%%%%%%%%%%%%%%%
legendStr = ["Continuous", transformName];

if fsUp >= 1e6
    upFsStr = [num2str(fsUp/1e6,'%.2f') ' MHz'];
else
    upFsStr = [num2str(fsUp/1e3,'%.1f') ' kHz'];
end

fig = figure(1);

spaceStr = ' ---------> ';
sgtitle(horzcat(transformName, ' Method', newline, ...
    'Bark-Weighted RMSE of Complex Response (20Hz-20kHz) = ', num2str(rootMeanSqComplexErrorWeighted), newline, ...
    'Filter Construction Time = ', num2str(procTime), ' seconds',  newline, ...
    'Original Sample Rate = ', num2str(fs/1000, '%.0f'), ' kHz', spaceStr, ...
    'Upsample Rate = ', upFsStr), ...
    fontsize = 24)

% time plot

subplot(3,1,1)
plot(t,h0,LineWidth=3)
hold on 
plot(t,y,LineWidth=2)
hold off
legend(legendStr, Location='northeast')
title(horzcat('Time RMSE (0-0.01s) = ', num2str(timeRMSE,'%.2E'), ...
'                ' ...
, 'Latency Due to FIR Anti-Alias Filters = ', num2str((delay*T)*1000,'%.2f'), 'ms'))
xlabel("Time (s)")
ylabel("Normalized Amplitude")
xlim([0 0.01])
set(gca,fontsize=18);

% magnitude plot
subplot(3,1,2)
semilogx(f,mag2db(abs(H0)),LineWidth=3)
hold on
semilogx(f,mag2db(abs(H1)),LineWidth=2)
xline(testFreq,LineWidth=2,Label=['Error at' newline '20kHz =' newline num2str(magError,'%.2f') ...
    'dB'],Color='k',LineStyle=':',FontSize=18,LabelOrientation='horizontal',...
    LabelHorizontalAlignment='left',LabelVerticalAlignment='top')
hold off
legend(legendStr, Location='southwest')
title(['Bark-Weighted Magnitude RMSE (20Hz-20kHz)  = ' num2str(rootMeanSqMagErrorWeighted,'%.2f') ' dB'])
xlabel("Frequency (Hz)")
ylabel("Magnitude (dB)")
xlim([0 fs/2+0.1*fs+2000])
ylim([-40 24])
set(gca,fontsize=18);

% phase plot
subplot(3,1,3)
semilogx(f,rad2deg(angle(H0)),LineWidth=3)
hold on
semilogx(f,rad2deg(H1ang),LineWidth=2)
xline(testFreq,LineWidth=2,Label=['Error at' newline '20kHz =' newline num2str(phaseError,'%.1f') char(176) newline newline newline], ...
    Color='k',LineStyle=':',FontSize=18,LabelOrientation='horizontal',...
    LabelHorizontalAlignment='left',LabelVerticalAlignment='top')
hold off
legend(legendStr, Location='southwest')
title(['Bark-Weighted Phase RMSE (20Hz-20kHz) = ' num2str(rootMeanSqPhaseErrorWeighted,'%.2f') ' ' char(176)])
xlim([0 fs/2+0.1*fs+2000])
xlabel("Frequency (Hz)")
ylabel("Phase Angle (Deg)")
set(gca,fontsize=18);
fig.WindowState = "maximized";
 
%%
function [upFilts, downFilts] = getOverSamplingFilters(numStages)
% Returns cells containing interpolation and decimation filters for each
% stage of X2 oversampling

upFilts = cell(numStages,1);
downFilts = cell(numStages,1);

    for stage = 1:numStages   
        % set transition bandwidths 
        if stage == 1
            twUp = single(0.05);
            twDown = single(0.06);
        else
            twUp = single(0.10);
            twDown = single(0.12);
        end
        
        % set stopband attenuations 
        gaindBStartUp    = -90.0;
        gaindBStartDown  = -75.0;
        gaindBFactorUp   =  10.0;
        gaindBFactorDown =  10.0;
        
        SBAup=gaindBStartUp + gaindBFactorUp * (stage-1);
        SBAdown=gaindBStartDown + gaindBFactorDown * (stage-1);
        
        % create the filters 
        upFilts{stage} = getUpFilts(SBAup,twUp);
        downFilts{stage} = getDownFilts(SBAdown, twDown);
    end
end

%%
function [c] = getUpFilts(amplitudedB, normalisedTransitionWidth)
% returns a single X2 interpolation filter
    c = designHalfbandFIR(TransitionWidth=normalisedTransitionWidth, ...
                            StopbandAttenuation=-1*amplitudedB, SystemObject=true, ...
                            Structure='interp', DesignMethod="equiripple", Verbose=true);
end

%%
function [c] = getDownFilts(amplitudedB, normalisedTransitionWidth)
% returns a single X2 decimation filter
    c = designHalfbandFIR(TransitionWidth=normalisedTransitionWidth, ...
                            StopbandAttenuation=-1*amplitudedB, SystemObject=true, ...
                            Structure='decim', DesignMethod="equiripple", Verbose=true);
end
%%
function [b, a] = invFreqzMagOnly(bs, as, fs, Nfft, NZ, NP)
% Constructs a minimum phase repsonse around the magnitude response of a
% continous-time filter defined by bs/as using the cepstral method. It then
% passes that complex response to infreqz to be discritized by
% minimization of the error in the complex responses.

% bs: s-domain numerator 
% as: s-domain denominator 
% fs: sample rate for discritization 
% Nfft: fft length (number of frequencies at which to sample
    % analog freq response including negative frequencies)
% Nz: desired number of zeros
% Np: desired number of poles

% Adapted from "Physical Audio Signal Processing" by Julius Orion Smith III, November 8, 2010
% https://www.dsprelated.com/freebooks/pasp/Fitting_Filters_Measured_Amplitude.html

    fk = fs*[0:Nfft/2]/Nfft; % fft frequency grid (nonneg freqs)
    radPerSec = 2*pi*fk;
    H0 = freqs(bs,as,radPerSec); % analog frequency response sampled at fk  
    Gfk = abs(H0);
    Ns = length(Gfk);

    S = [Gfk,Gfk(Ns-1:-1:2)]; % install negative-frequencies
    Sdb = mag2db(S);

    c = ifft(Sdb); % compute real cepstrum from log magnitude spectrum
    % Fold cepstrum to reflect non-min-phase zeros inside unit circle:
    cf = [c(1), c(2:Ns-1)+c(Nfft:-1:Ns+1), c(Ns), zeros(1,Nfft-Ns)];
    Cf = fft(cf); % = dB_magnitude + j * minimum_phase
    Smp = 10 .^ (Cf/20); % minimum-phase spectrum
    
    Smpp = Smp(1:Ns); % nonnegative-frequency portion
    % wt = 1 ./ (fk+1); % typical weight fn for audio
    wk = 2*pi*fk/fs;
    wt = getBkWts(fk);
    [b,a] = invfreqz(Smpp,wk,NZ,NP,wt,1e2,0.001);

end

%%
function [b, a, compTime] = nyquistBandTransform(bs, as, fs, order)
% Returns a discritized version of the continous-time filter, bs/as. The
% discritization is carried out using the Nyquist band transform devloped
% in Nyquist Band Transform: An Order-Preserving Transform for Bandlimited
% Discretization by CHAMP C. DARABUNDIT, JONATHAN S. ABEL, and DAVID
% BERNERS found at
% https://ccrma.stanford.edu/~champ/files/Darabundit2022_NBT.pdf

% bs: s-domain numerator 
% as: s-domain denominator 
% fs: sample rate for discritization 
% order: order of bs, as - these should be the same, zero pad if necessary

% b: z-domain numerator
% a: z-domain denominator
% compTime: computation time excluding matrix construction which could be
% pre-computed in many use cases

    N = order;
    Omega0 = pi*fs; % nyquist frequency in rad/sec
    T = 1/fs; % sample period 

    % EQ. 39 in Nyquist Band Transform: An Order-Preserving Transform for
    % Bandlimited Discretization with modification: "The formulation in Eq.
    % (39) can also be used to apply the first transform Eq. (26) by swapping
    % Omega0^2 for -Omega0^2 and replacing gamma with −2*Omega0*OmegaC". OmegaC is
    % set equal to Omega0
    A0 = zeros(2*N+1,N+1);
    for n = 0:N
        for k = 0:n
            A0(N-n+2*k+1,(n+1)) = (-2*Omega0^2)^(N-n)*nchoosek(n,k)*(-1*Omega0^2)^(n-k);
        end
    end
    
    A0 = flip(A0,1);

    % gamma is a free paramater that allows perfect matching for one
    % frequency via EQ. 64 in Nyquist Band Transform: An Order-Preserving Transform for
    % Bandlimited Discretization
    % Uplsilon = 2*(((2/T)*tan((Omega_a*T)/2))/Omega_a)*sqrt(1-((Omega_a*T)/pi)^2);
    
    % "If there is no a priori of the system, a possible choice for γ is to set
    % Omega_a = (π*fs)/2: half the Nyquist limit. This results in a γ =
    % 4*(3^0.5)*π*fs^2 ≈ 2.2*Omega0^2"    
    % gamma = 2.2*Omega0^2;

    % Alternately, gamma can be optimized to give the smallest amount of
    % frequency warping accross some bandwidth with some weighting. The
    % following values are optimized to give the least mean absolute error
    % in frequency mapping from 20Hz-20kHz for each sample rate:

    % % MAE 20Hz-20kHz
    % switch fs
    %     case 48e3
    %         gammaHat = 2.0538;
    %     case 96e3 
    %         gammaHat = 2.0185;
    %     case 192e3 
    %         gammaHat = 2.0048;
    %     case 384e3 
    %         gammaHat = 2.0012;
    %     case 768e3 
    %         gammaHat = 2.0003;
    %     otherwise
    %         gammaHat = 2;    
    % end

    % Bark-Weighted MSE, 20Hz-20kHz
    switch fs
        case 48e3
            gammaHat = 2.1826;
        case 96e3 
            gammaHat = 2.0532;
        case 192e3 
            gammaHat = 2.0130;
        case 384e3 
            gammaHat = 2.0032;
        case 768e3 
            gammaHat = 2.0008;
        otherwise
            gammaHat = 2;    
    end

    gamma = gammaHat*Omega0^2;

    % EQ. 39 in Nyquist Band Transform: An Order-Preserving Transform for
    % Bandlimited Discretization.
    % OmegaC is set equal to Omega0
    A = zeros(2*N+1,N+1);
    for n = 0:N
        for k = 0:n
            A(N-n+2*k+1,(n+1)) = (gamma)^(N-n)*nchoosek(n,k)*(Omega0^2)^(n-k);
        end
    end
    
    A = flip(A,1);
    
    Aplus = pinv(A);

    tic;
    
    % first forward transform
    kb = A0*bs.'; 
    ka = A0*as.';

    % Stabilize the mapped coefficients κa and enforce minimum/maximum phase
    % on κb
    [z,p,k] = tf2zp(kb.',ka.');
    pImag = imag(p);
    pReal = real(p);
    pRealStable = abs(pReal)*-1;
    pStable = pRealStable+pImag;
    
    zImag = imag(z);
    zReal = real(z);
    zRealStable = abs(zReal)*-1;
    zMinPhase = zRealStable+zImag;
    
    [kbStable, kaStable] = zp2tf(zMinPhase,pStable,k);

    % second inverse transform
    cb = Aplus*kbStable.';
    ca = Aplus*kaStable.';

    % bilinear transform
    sdtf = tf(cb.', ca.');
    opts = c2dOptions;
    opts.Method = 'tustin';
    zdtf = c2d(sdtf,T,opts);

    % discrete time coefficients 
    b = zdtf.Numerator{1}; 
    a = zdtf.Denominator{1};  

    compTime = toc;
end

%%
function bkWts = getBkWts(freq)
    % Returns an array of weights the same length as freq where each weight
    % equals 1 divided by the bandwidth of the Bark band that the
    % corresponding frequency falls in for frequencies less than 27kHz and
    % 1/f for frequencies above that.
    
    % freq: An array of frequencies in Hz

    barkBandEdges = [20, 100, 200, 300, 400, 510, ...
        630, 770, 920, 1080, 1270, 1480, 1720, ...
        2000, 2320, 2700, 3150, 3700, 4400, 5300, ...
        6400, 7700, 9500, 12000, 15500, 20500, 27001];

    if any(freq < 0)
        error("min frequency = 0 Hz")
    end

    % make array of bandwidths corresponding to each Bark band
    barkBandWidths = zeros(length(barkBandEdges)-1,1);
    for idx = 1:length(barkBandWidths)
        barkBandWidths(idx) = barkBandEdges(idx+1)-barkBandEdges(idx);
    end

    bkWts = zeros(length(freq),1);

    % for each frequency, find the Bark band that it falls into and fill the
    % corresponding index in bkWts with 1 divided by the bandwidth of that
    % band
    for idx = 1:length(bkWts)
        if freq(idx) < barkBandEdges(2)
            bkWts(idx) = 1/barkBandWidths(1);    
        elseif freq(idx) < barkBandEdges(3)
            bkWts(idx) = 1/barkBandWidths(2);
        elseif freq(idx) < barkBandEdges(4)
            bkWts(idx) = 1/barkBandWidths(3);        
        elseif freq(idx) < barkBandEdges(5)
            bkWts(idx) = 1/barkBandWidths(4);
        elseif freq(idx) < barkBandEdges(6)
            bkWts(idx) = 1/barkBandWidths(5);        
        elseif freq(idx) < barkBandEdges(7)
            bkWts(idx) = 1/barkBandWidths(6);
        elseif freq(idx) < barkBandEdges(8)
            bkWts(idx) = 1/barkBandWidths(7);
        elseif freq(idx) < barkBandEdges(9)
            bkWts(idx) = 1/barkBandWidths(8);
        elseif freq(idx) < barkBandEdges(10)
            bkWts(idx) = 1/barkBandWidths(9);
        elseif freq(idx) < barkBandEdges(11)
            bkWts(idx) = 1/barkBandWidths(10);
        elseif freq(idx) < barkBandEdges(12)
            bkWts(idx) = 1/barkBandWidths(11);
        elseif freq(idx) < barkBandEdges(13)
            bkWts(idx) = 1/barkBandWidths(12);
        elseif freq(idx) < barkBandEdges(14)
            bkWts(idx) = 1/barkBandWidths(13);
        elseif freq(idx) < barkBandEdges(15)
            bkWts(idx) = 1/barkBandWidths(14);
        elseif freq(idx) < barkBandEdges(16)
            bkWts(idx) = 1/barkBandWidths(15);
        elseif freq(idx) < barkBandEdges(17)
            bkWts(idx) = 1/barkBandWidths(16);
        elseif freq(idx) < barkBandEdges(18)
            bkWts(idx) = 1/barkBandWidths(17);
        elseif freq(idx) < barkBandEdges(19)
            bkWts(idx) = 1/barkBandWidths(18);
        elseif freq(idx) < barkBandEdges(20)
            bkWts(idx) = 1/barkBandWidths(19);
        elseif freq(idx) < barkBandEdges(21)
            bkWts(idx) = 1/barkBandWidths(20);
        elseif freq(idx) < barkBandEdges(22)
            bkWts(idx) = 1/barkBandWidths(21);
        elseif freq(idx) < barkBandEdges(23)
            bkWts(idx) = 1/barkBandWidths(22);
        elseif freq(idx) < barkBandEdges(24)
            bkWts(idx) = 1/barkBandWidths(23);
        elseif freq(idx) < barkBandEdges(25)
            bkWts(idx) = 1/barkBandWidths(24);
        elseif freq(idx) < barkBandEdges(26)
            bkWts(idx) = 1/barkBandWidths(25);
        elseif freq(idx) < barkBandEdges(27)
            bkWts(idx) = 1/barkBandWidths(26);
        else 
            bkWts(idx) = 1/(freq(idx)); % 1/f weighting for everything else
        end
    end
end