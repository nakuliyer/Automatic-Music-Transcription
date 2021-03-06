function [estimated_pr, pr, H, W] = smaragdis_nmf(wav_file, midi_file)
  % Warning: this is written for Octave and not tested with MATLAB

  % ***Note to self***
  % I'm worried that the wav file and midi file are not aligned properly

  % Setup
  % 0. Generate 16KHz wave file from midi
  
  % Testing
  % 1. Compute STFT of wave file
  % 2. Run NMF on the spectrogram, starting with random matrices
  % 3. Apply a threshold to the piano roll

  more off;

  % Open wav file
  [y,fs,bps] = wavread(wav_file);
  % Compute the STFT on 128ms frames with 10ms hops
  isOctave = exist('OCTAVE_VERSION') ~= 0;
  if isOctave
    [S, f, spec_t] = specgram(y, 2048, fs, hanning(.128*fs), 2048 - 160); % Needs to be spectrogram in MATLAB  
  else
    [S, f, spec_t] = spectrogram(y, 2048, 2048-160, 2048, fs);
  end

  % Compute the FFT magnitudes
  magS = abs(S);

  %magS(1:40,1:40)
  %pause

  num_steps = size(S,2);  

  % Add the midi library
  addpath('../lib/matlab-midi/src');
  % Open the MIDI file
  midi = readmidi(midi_file);
  notes = midiInfo(midi,0);
  % T is in increments of 10ms, the same as our STFT'd wav file
  [pr, t, nn] = piano_roll(notes);

  % Only display a subset of the ground truth for comparison to computed piano roll later
  subset = 2000;
  view_piano_roll(t(1:subset),nn,pr(:,1:subset), 'Ground truth')
  
  % Run NMF on the spectrogram
  
  % Randomly generate W and H
  k = 25;
  W = rand(1024, k);
  %H = rand(k, num_steps);

  % Perform on subset 
  magS = magS(:,1:subset);
  H = rand(k, subset);
  
  V = magS; 

  % Iterate on W and H until convergence
  for i=1:200 % Use actual stopping criteria here
      fprintf('Update #%d:\n', i);
      
      % Apply update rule to W and H
      %Wnew = W + (W*H - magS) * H';
      %Hnew = H + W'*(W*H - magS);
      H = H .* ((W'*V) ./ (W'*W*H + 1e-9));
      W = W .* ((V*H') ./ (W*H*H' + 1e-9));
 
      % Compute the Frobenius norm
      S_norm = norm(V - W*H, 'fro'); % Shows how close W*H is to the spectrogram
      fprintf('S_norm: %g\n\n', S_norm);
  end
  
  % Threshold the values in the H piano roll matrix

  eta = .1
  estimated_pr = zeros(size(pr,1), size(pr,2));
  H = H ./ max(max(H)); % Adding this to make the threshold meaningful
  for i=1:k
      for j=1:subset
      	  if (H(i,j) > eta)
	     estimated_pr(i,j) = 1;
	  end
      end
  end
  
  view_piano_roll(spec_t(1:subset), nn, estimated_pr(:,1:subset), 'SVM output');
  
end

