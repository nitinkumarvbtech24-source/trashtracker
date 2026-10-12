document.addEventListener('DOMContentLoaded', () => {
    const dropzone = document.getElementById('dropzone');
    const fileInput = document.getElementById('fileInput');
    const confidenceSlider = document.getElementById('confidenceSlider');
    const confidenceValue = document.getElementById('confidenceValue');
    const btnAnalyze = document.getElementById('btnAnalyze');
    const spinner = document.getElementById('spinner');
    const samplesContainer = document.getElementById('samplesGrid');

    const origImage = document.getElementById('origImage');
    const resultImage = document.getElementById('resultImage');
    const origPlaceholder = document.getElementById('origPlaceholder');
    const resultPlaceholder = document.getElementById('resultPlaceholder');

    const totalTrashEl = document.getElementById('totalTrash');
    const avgConfEl = document.getElementById('avgConf');
    const inferenceTimeEl = document.getElementById('inferenceTime');
    const riskBanner = document.getElementById('riskBanner');
    const riskTitle = document.getElementById('riskTitle');
    const riskRec = document.getElementById('riskRec');
    const detectionsTableBody = document.getElementById('detectionsTableBody');

    const globalScansEl = document.getElementById('globalScans');
    const globalDetectionsEl = document.getElementById('globalDetections');

    let selectedFile = null;
    let selectedSample = null;

    // Load test sample images
    fetch('/api/samples')
        .then(res => res.json())
        .then(data => {
            if (data.samples && data.samples.length > 0) {
                samplesContainer.innerHTML = '';
                data.samples.forEach(sample => {
                    const img = document.createElement('img');
                    img.src = `/static/samples/${sample}`;
                    img.className = 'sample-thumb';
                    img.title = sample;
                    img.addEventListener('click', () => selectSample(sample, img));
                    samplesContainer.appendChild(img);
                });
            }
        }).catch(err => console.error('Failed to load samples:', err));

    // Confidence slider event
    confidenceSlider.addEventListener('input', (e) => {
        confidenceValue.textContent = `${Math.round(e.target.value * 100)}%`;
    });

    // Dropzone Click & Drag events
    dropzone.addEventListener('click', () => fileInput.click());

    dropzone.addEventListener('dragover', (e) => {
        e.preventDefault();
        dropzone.classList.add('dragover');
    });

    dropzone.addEventListener('dragleave', () => dropzone.classList.remove('dragover'));

    dropzone.addEventListener('drop', (e) => {
        e.preventDefault();
        dropzone.classList.remove('dragover');
        if (e.dataTransfer.files && e.dataTransfer.files[0]) {
            handleFileSelect(e.dataTransfer.files[0]);
        }
    });

    fileInput.addEventListener('change', (e) => {
        if (e.target.files && e.target.files[0]) {
            handleFileSelect(e.target.files[0]);
        }
    });

    function handleFileSelect(file) {
        selectedFile = file;
        selectedSample = null;
        
        // Remove active class from sample thumbnails
        document.querySelectorAll('.sample-thumb').forEach(thumb => thumb.classList.remove('active'));

        const reader = new FileReader();
        reader.onload = (e) => {
            origImage.src = e.target.result;
            origImage.style.display = 'block';
            origPlaceholder.style.display = 'none';

            // Reset result preview until analyze clicked
            resultImage.style.display = 'none';
            resultPlaceholder.style.display = 'flex';
        };
        reader.readAsDataURL(file);
    }

    function selectSample(sampleName, thumbEl) {
        selectedSample = sampleName;
        selectedFile = null;

        document.querySelectorAll('.sample-thumb').forEach(thumb => thumb.classList.remove('active'));
        thumbEl.classList.add('active');

        origImage.src = `/static/samples/${sampleName}`;
        origImage.style.display = 'block';
        origPlaceholder.style.display = 'none';

        resultImage.style.display = 'none';
        resultPlaceholder.style.display = 'flex';
    }

    // Analyze Button Click
    btnAnalyze.addEventListener('click', () => {
        if (!selectedFile && !selectedSample) {
            alert('Please select or upload an image first!');
            return;
        }

        const formData = new FormData();
        formData.append('confidence', confidenceSlider.value);

        if (selectedFile) {
            formData.append('file', selectedFile);
        } else if (selectedSample) {
            formData.append('sample', selectedSample);
        }

        // Show spinner
        btnAnalyze.disabled = true;
        spinner.style.display = 'inline-block';

        fetch('/api/detect', {
            method: 'POST',
            body: formData
        })
        .then(res => res.json())
        .then(data => {
            btnAnalyze.disabled = false;
            spinner.style.display = 'none';

            if (data.error) {
                alert(`Error: ${data.error}`);
                return;
            }

            renderResults(data);
        })
        .catch(err => {
            btnAnalyze.disabled = false;
            spinner.style.display = 'none';
            alert(`Analysis failed: ${err}`);
        });
    });

    function renderResults(data) {
        // Display AI Annotated Result Image
        resultImage.src = data.result_url + '?t=' + new Date().getTime();
        resultImage.style.display = 'block';
        resultPlaceholder.style.display = 'none';

        // Summary metrics
        totalTrashEl.textContent = data.summary.total_trash_detected;
        avgConfEl.textContent = `${data.summary.average_confidence}%`;
        inferenceTimeEl.textContent = `${data.summary.inference_time_ms} ms`;

        // Risk banner update
        riskBanner.className = `risk-banner ${data.summary.risk_color}`;
        riskTitle.textContent = `Status: ${data.summary.risk_level}`;
        riskRec.textContent = data.summary.recommendation;

        // Global stats
        if (data.global_stats) {
            globalScansEl.textContent = data.global_stats.total_scans;
            globalDetectionsEl.textContent = data.global_stats.total_detected_trash;
        }

        // Detections Table
        detectionsTableBody.innerHTML = '';
        if (data.detections.length === 0) {
            detectionsTableBody.innerHTML = `<tr><td colspan="4" style="text-align:center; color: var(--text-muted); padding: 20px;">No trash objects detected at ${Math.round(data.summary.confidence_threshold_used * 100)}% confidence threshold.</td></tr>`;
        } else {
            data.detections.forEach(det => {
                const tr = document.createElement('tr');
                tr.innerHTML = `
                    <td>#${det.id}</td>
                    <td><span class="badge badge-green">Trash</span></td>
                    <td><strong>${det.confidence}%</strong></td>
                    <td>[${det.box[0]}, ${det.box[1]}, ${det.box[2]}, ${det.box[3]}]</td>
                `;
                detectionsTableBody.appendChild(tr);
            });
        }
    }
});
