function [estimated_pr, pr] = poliner_svm(wav_train, midi_train, wav_test, midi_test)
  % Warning: this is written for Octave and not tested with MATLAB
  % This also uses libsvm. The libsvm I have included has been built for Octave

  % ***Note to self***
  % I'm worried that the wav file and midi file are not aligned properly

  % Setup
  % 0. Generate 16KHz wave file from midi

  % Training steps
  % 1. Compute STFT of wave file
  % 2. Normalize the STFT
  % 3. Train SVMs matched to the midi file

  % Testing steps
  % 4. Run SVM on new wave file
  % 5. Run HMM on SVM piano roll output 
  piano_low = 21;
  piano_high = 107;
  more off;

  % Open wav file
  [y,fs,bps] = wavread(wav_train);
  [y_2,fs_2,bps_2] = wavread(wav_test);
  % length(y)
  % fs
  % .128*fs
  %.01*fs
  % Compute the STFT on 128ms frames with 10ms hops
  isOctave = exist('OCTAVE_VERSION') ~= 0;
  if isOctave
    [S, f, spec_t] = specgram(y, 2048, fs, hanning(.128*fs), 2048 - 160); % Needs to be spectrogram in MATLAB  
  else
    [S, f, spec_t] = spectrogram(y, 2048, 2048-160, 2048, fs);
    [S_2, f_2, spec_t_2] = spectrogram(y_2, 2048, 2048-160, 2048, fs_2);

    %[S, f, spec_t] = qgram(y, fs,1); 
  end

  size(S) 
  %spec_t(end)
  % pause
  % Compute the FFT magnitudes
  magS = abs(S);
  magS_2 = abs(S_2);
  % Normalize, whiten the FFT magnitudes (to-do)
    
  % Add the libsvm and midi libraries  
  addpath('../lib/libsvm');
  addpath('../lib/matlab-midi/src');
  

  % Open the MIDI file
  midi = readmidi(midi_train);
  midi_2 = readmidi(midi_test);
  notes = midiInfo(midi,0);
  notes_2 = midiInfo(midi_2,0);
  %notes = [notes; notes_2];
  % T is in increments of 10ms, the same as our STFT'd wav file
  [pr, t, nn] = piano_roll(notes);
  [pr_2,t_2,nn_2]= piano_roll(notes_2);
  
  nn_total = linspace(piano_low,piano_high,87);
  %widen piano rolls to go from 21 to 107
  pr = [pr;zeros(nn(1)-piano_low,size(pr,2))];
  pr = [pr;zeros(piano_high-nn(end),size(pr,2))];
  
  pr_2 = [pr_2;zeros(nn(1)-piano_low,size(pr_2,2))];
  pr_2 = [pr_2;zeros(piano_high-nn(end),size(pr_2,2))];
  %notes
  pause
  
  
  size(pr)
  % pause
  % sum(pr,2)

  % Only display a subset of the ground truth for comparison to computed piano roll later
  subset = 2000;
  view_piano_roll(t_2(1:subset),nn_total,pr_2(:,1:subset), 'Ground truth')
  %view_piano_roll(spec_t(1:subset), nn, estimated_pr(:,1:subset));

  % This is a way to convert midi to wav, but it wasn't working for me:
  % [y,Fs] = midi2audio(midi);
  % wavwrite(y,Fs,'out.wav');
  
  % Train 88 SVMs for each piano key
  % For reasons I do not understand, the note number goes from 20s to 90s
  num_notes = 87; %88 since there are 88 piano keys, 21 to 107, but highest note is not used
  svm_models = cell(num_notes); 
  means = cell(num_notes,1);
  vars = cell(num_notes,1);
  for i=1:num_notes
      %index of i'th piano note in nn
      fprintf('Training SVM %d...\n', i);
      note_vec = pr(i,:);
      
      if sum(note_vec) == 0
      	 continue
      end

      % Randomly sample postive examples (<=100)
      pos = find(note_vec == 1);

      num_examples = 0;
      if length(pos) < 100
      	 num_examples = length(pos);
      else
	 num_examples = 100;
         pos = pos(randperm(length(pos)));
      end

      pos = pos(1:num_examples);
      pos_examples = magS(:,pos);

      % Randomly sample same number of negative examples
      neg = find(note_vec == 0);
      neg = neg(randperm(length(neg)));
      neg = neg(1:num_examples);
      neg_examples = magS(:,neg);
      
      midi_note = nn_total(i);
      
       if (midi_note >= 21 && midi_note <= 83) %0-2K
           pos_examples = pos_examples(1:256, :);
           neg_examples = neg_examples(1:256, :);
       elseif (midi_note > 83 && midi_note <= 95) %1K-3K
           pos_examples = pos_examples(129:384, :);
           neg_examples = neg_examples(129:384, :);              
       else                                          %2K-4K
           pos_examples = pos_examples(257:512, :);
           neg_examples = neg_examples(257:512, :);   
       end

      % Train SVM on these samples
      training_labels = [ones(1,num_examples) -1*ones(1,num_examples)]';
      training_input = [pos_examples neg_examples]';
      means{i} = mean(training_input);
      training_input = bsxfun(@minus,training_input,means{i});
      vars{i} = std(training_input);
      training_input = bsxfun(@rdivide, training_input, vars{i}); 
      svm_models{i} = svmtrain(training_labels, training_input, '-s 1 -t 2 -c .1 -q'); 
  end

  % Just to test this for now, rerun these svms on the wave file and generate a piano roll
  % estimated_pr = zeros(size(pr));
  estimated_pr = zeros(num_notes, size(S_2,2));
  estimated_pr = estimated_pr-1;
  % pr time length should equal S time length, but they're off by a few hundred samples, so I'm suspicious that timidity is adding extra time somewhere
  training_pr = zeros(num_notes,size(S,2));
  training_pr = training_pr-1;

  for i=1:subset % size(S,2)
      fprintf('Predicting time step %d of %d\n', i,subset);
      for j=1:num_notes
        if isempty(svm_models{j})
	      % We had no notes to train on 
	      continue
        end
        midi_note = nn_total(j);
        if (midi_note >= 21 && midi_note <= 83) %0-2K
           feature = magS_2(1:256, i);
        elseif (midi_note > 83 && midi_note <= 95) %1K-3K
           feature = magS_2(129:384, i);          
        else                                          %2K-4K
           feature = magS_2(257:512, i);
        end        
        

      	  % Evaluate note SVM on STFT 
        feature = feature - means{j}';
        feature = feature./vars{j}';

	    [predict_label, accuracy, dec] = svmpredict(rand(1), feature', svm_models{j},'-q');
	    estimated_pr(j,i) = predict_label; % Converts -1 -> 0, 1 -> 1
        
        %also evaluate svm on training wav file to get training_pr
        midi_note_train = nn_total(j);
        if (midi_note_train >= 21 && midi_note_train <= 83) %0-2K
           feature = magS(1:256, i);
        elseif (midi_note_train > 83 && midi_note_train <= 95) %1K-3K
           feature = magS(129:384, i);          
        else                                          %2K-4K
           feature = magS(257:512, i);
        end         
        feature = feature - means{j}';
        feature = feature./vars{j}'; 
	    [predict_label, accuracy, dec] = svmpredict(rand(1), feature', svm_models{j},'-q');
        training_pr(j,i) = predict_label;
        
      end
  end
  
  view_piano_roll(spec_t_2(1:subset), nn_total, estimated_pr(:,1:subset), 'SVM output');
  view_piano_roll(spec_t(1:subset), nn_total, training_pr(:,1:subset), 'training SVM output');
  
  fprintf('Running HMM on SVM output\n');

  % === HMM ===

  % Run a hidden markov model over the piano roll for smoothing the raw log posterior probabilities
  % Estimation of priors and transition matrix can be done using MIDI files (ground truth)
  % Estimation of emission matrix should be done using predict_label from SVM
  
  notes_list = unique(notes(:,3)); %list of notes that are played on training data
  true_labels = zeros(size(training_pr));
  smooth_labels = zeros(size(training_pr));
  smooth_labels = smooth_labels-1;
  true_labels = bsxfun(@minus,true_labels,1); %initialize true_labels to -1

  for i=1:size(nn,2)
    fprintf('Smoothing note %d\n', i);
    cur_note = nn(i);

  % If cur_note is not actually played in song, skip it
    if (isempty(find(notes_list == cur_note, 1)))
        continue;
    end

  % Estimate prior
    on_times = notes(notes(:,3) == cur_note,:);
    on_time_total = 0;
    time_total = t(end); %using this as proxy for total length of time
    for j = 1:size(on_times,1)
        %sum the differences between on and off time of note to get total
        %on_time
        on_time_total = on_time_total + (on_times(j,6) - on_times(j,5));
    end

    prior_on = on_time_total / time_total;
    prior_off = 1 - prior_on;

  % Estimate a transition matrix
  % Probability of becoming on from off should be total number of on's
  % divided by total number of off frames in song..? And vice versa as well
    total_frames = time_total * 100;
    
  % trans_mat(1,2) will be probability of going to on from off
    trans_mat = zeros(2,2);
    trans_mat(1,2) = size(on_times,1) / (prior_off*total_frames);
    trans_mat(2,1) = size(on_times,1) / (prior_on*total_frames);
    trans_mat(1,1) = 1 - trans_mat(1,2);
    trans_mat(2,2) = 1 - trans_mat(2,1);

  % Estimate emission matrix
  
  % Construct a matrix of true labels of same size as estimated_pr
  % if end of interval occurs after start of note onset
  
  % if note onset starts at 15.000 seconds, ends at 16.000 seconds, then
  % frames completely in the range 14.872 to 16.128 should contain it.
  % this corresponds to frame 1488 through 1600
    
    for j = 1:size(on_times,1)
        start_frame = max(ceil((on_times(j,5)-0.128)*100),1);
        end_frame = min(floor(on_times(j,6)*100),size(true_labels,2));
        true_labels(i,start_frame:end_frame)=ones(1,end_frame-start_frame+1);
    end
    %compare estimated_pr(i,j) with...true_labels(i,j)
    em_mat = zeros(2,2);
    diffs = training_pr(i,1:subset)-true_labels(i,1:subset);
    adds = training_pr(i,1:subset)+true_labels(i,1:subset);
    em_mat(1,2)= sum(diffs==2);%true value is -1, estimated is 1
    em_mat(2,1)= sum(diffs==-2);%true value is 1, estimated is -1
    em_mat(1,1)= sum(adds==-2); %truevalue is -1, estimated is -1
    if em_mat(1,1)+em_mat(2,1)==subset
        continue; %then there's nothing to smooth
    end
    em_mat(2,2)= sum(adds==2);
    if sum(em_mat(1,:))~=0
        em_mat(1,:)=em_mat(1,:)/sum(em_mat(1,:));
    else
        continue;
    end
    if sum(em_mat(2,:))~=0
        em_mat(2,:)=em_mat(2,:)/sum(em_mat(2,:));
    else
        continue;
    end
    %SEQ must be 1's and 2's.
    SEQ = estimated_pr(i,1:2000);  
    SEQ(SEQ==1)=2;
    SEQ(SEQ==-1)=1;
    trans_mat
    em_mat
    
    STATES = hmmviterbi(SEQ,trans_mat,em_mat);
    STATES(STATES==1)=-1;
    STATES(STATES==2)=1;
    smooth_labels(i,1:subset)= STATES;
    
  end
  view_piano_roll(spec_t_2(1:subset), nn_2, smooth_labels(:,1:subset), 'Smoothed output');  
  %Calculate error for raw and smoothed labels
  [AccS, E_totS, E_subS, E_missS, E_faS] = calc_error(pr_2,smooth_labels, 2000);
  [AccR, E_totR, E_subR, E_missR, E_faR] = calc_error(pr_2,estimated_pr, 2000);
end

