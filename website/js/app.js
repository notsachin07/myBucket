document.addEventListener('DOMContentLoaded', () => {
  const fileInput = document.getElementById('fileInput');
  const dropzone = document.getElementById('dropzone');
  const dropzoneContent = document.getElementById('dropzone-content');
  const previewImage = document.getElementById('preview-image');
  const renameGroup = document.getElementById('rename-group');
  const fileNameInput = document.getElementById('fileName');
  const folderPathInput = document.getElementById('folderPath');
  const btnUpload = document.getElementById('btn-upload');
  const btnText = btnUpload.querySelector('.btn-text');
  const uploadLoader = document.getElementById('upload-loader');
  const statusMessage = document.getElementById('status-message');

  const settingsModal = document.getElementById('settings-modal');
  const apiUrlInput = document.getElementById('apiUrl');
  const btnSettings = document.getElementById('btn-settings');
  const btnSaveSettings = document.getElementById('btn-save-settings');

  let selectedFile = null;
  let originalExtension = '';

  // Initialize Settings
  const initSettings = () => {
    const currentUrl = ApiService.getApiUrl();
    if (!currentUrl) {
      showSettings();
    }
  };

  const showSettings = () => {
    apiUrlInput.value = ApiService.getApiUrl();
    settingsModal.classList.add('active');
  };

  const saveSettings = () => {
    const url = apiUrlInput.value.trim();
    if (url) {
      ApiService.setApiUrl(url);
      settingsModal.classList.remove('active');
    }
  };

  btnSettings.addEventListener('click', showSettings);
  btnSaveSettings.addEventListener('click', saveSettings);

  // File Selection Logic
  const handleFile = (file) => {
    if (!file || !file.type.startsWith('image/')) return;
    
    selectedFile = file;
    const fileName = file.name;
    const extIndex = fileName.lastIndexOf('.');
    
    if (extIndex !== -1) {
      fileNameInput.value = fileName.substring(0, extIndex);
      originalExtension = fileName.substring(extIndex);
    } else {
      fileNameInput.value = fileName;
      originalExtension = '';
    }

    // Show preview
    const reader = new FileReader();
    reader.onload = (e) => {
      previewImage.src = e.target.result;
      previewImage.style.display = 'block';
      dropzoneContent.style.display = 'none';
      renameGroup.style.display = 'block';
      btnUpload.disabled = false;
      hideStatus();
    };
    reader.readAsDataURL(file);
  };

  // Drag and Drop Events
  dropzone.addEventListener('click', () => fileInput.click());
  fileInput.addEventListener('change', (e) => handleFile(e.target.files[0]));

  ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
    dropzone.addEventListener(eventName, preventDefaults, false);
  });

  function preventDefaults(e) {
    e.preventDefault();
    e.stopPropagation();
  }

  ['dragenter', 'dragover'].forEach(eventName => {
    dropzone.addEventListener(eventName, () => dropzone.classList.add('drag-active'), false);
  });

  ['dragleave', 'drop'].forEach(eventName => {
    dropzone.addEventListener(eventName, () => dropzone.classList.remove('drag-active'), false);
  });

  dropzone.addEventListener('drop', (e) => {
    const dt = e.dataTransfer;
    const files = dt.files;
    handleFile(files[0]);
  });

  // Upload Logic
  const showStatus = (message, isError = false) => {
    statusMessage.textContent = message;
    statusMessage.className = isError ? 'status-error' : 'status-success';
    statusMessage.style.display = 'block';
  };

  const hideStatus = () => {
    statusMessage.style.display = 'none';
  };

  btnUpload.addEventListener('click', async () => {
    const apiUrl = ApiService.getApiUrl();
    if (!apiUrl) {
      showSettings();
      return;
    }

    if (!selectedFile) {
      showStatus('Please select a file first.', true);
      return;
    }

    const baseName = fileNameInput.value.trim();
    if (!baseName) {
      showStatus('File name cannot be empty.', true);
      return;
    }

    const finalFileName = originalExtension ? `${baseName}${originalExtension}` : baseName;
    const folderPath = folderPathInput.value.trim();

    // UI Loading State
    btnUpload.disabled = true;
    btnText.style.display = 'none';
    uploadLoader.style.display = 'block';
    hideStatus();

    const startTime = Date.now();
    const timerInterval = setInterval(() => {
      const elapsed = Math.floor((Date.now() - startTime) / 1000);
      if (elapsed >= 1) {
        showStatus(`Waking up server (Cold Start)... Please wait (${elapsed}s)`, false);
      }
    }, 1000);

    try {
      await ApiService.uploadFile(apiUrl, selectedFile, folderPath, finalFileName);
      
      clearInterval(timerInterval);
      showStatus('Upload completed successfully!');
      
      // Reset UI
      selectedFile = null;
      previewImage.style.display = 'none';
      previewImage.src = '';
      dropzoneContent.style.display = 'block';
      renameGroup.style.display = 'none';
      
    } catch (error) {
      clearInterval(timerInterval);
      showStatus(`Upload failed: ${error.message}`, true);
      btnUpload.disabled = false;
    } finally {
      clearInterval(timerInterval);
      btnText.style.display = 'block';
      uploadLoader.style.display = 'none';
    }
  });

  // Init
  initSettings();
});
