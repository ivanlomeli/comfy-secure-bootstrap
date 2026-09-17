# Workflows plantilla

Descarga estos `.json` y arrástralos al canvas de ComfyUI para empezar rápido.

## Cómo cargar un workflow

1. Abre ComfyUI en tu navegador.
2. Menú → *Load* (o arrastra el archivo `.json` al canvas).
3. Si faltan custom nodes o modelos, ComfyUI-Manager te ofrecerá instalar los faltantes.

## Workflows incluidos

Los `.json` no vienen en este repo por peso. Descárgalos de las fuentes oficiales:

### Image
- **SDXL base + refiner**: menu de ComfyUI → *Load Default* (ya viene incluido).
- **FLUX.1 dev básico**: https://comfyanonymous.github.io/ComfyUI_examples/flux/
- **ControlNet SDXL**: https://comfyanonymous.github.io/ComfyUI_examples/controlnet/

### Video
- **Wan 2.2 image-to-video**: https://github.com/kijai/ComfyUI-WanVideoWrapper/tree/main/example_workflows
- **HunyuanVideo T2V**: https://github.com/kijai/ComfyUI-HunyuanVideoWrapper/tree/main/example_workflows
- **AnimateDiff v3**: https://github.com/Kosinkadink/ComfyUI-AnimateDiff-Evolved/tree/main/example_workflows

### Portrait animation
- **Sonic (audio-driven)**: https://github.com/smthemex/ComfyUI-Sonic/tree/main/examples

### Upscale
- **SUPIR upscale**: https://github.com/kijai/ComfyUI-SUPIR/tree/main/examples

## Formato de workflow

Un workflow es JSON con dos formas:

1. **UI format** — lo que exportas desde ComfyUI con *Save*. Contiene posiciones de nodos, valores, etc. Sirve para colaboración humana.

2. **API format** — lo que se envía al endpoint `/prompt`. Es un dict `{node_id: {inputs, class_type}}` sin metadata de UI. Se obtiene con *Save (API Format)*.

Para automatización (batch generation desde Python), usa siempre API format.

## Ejemplo de invocación por API

```python
import requests, json, time

# Cargar workflow API format
with open('sdxl_batch.json') as f:
    workflow = json.load(f)

# Enviar prompt
r = requests.post('http://127.0.0.1:8188/prompt', json={'prompt': workflow})
prompt_id = r.json()['prompt_id']

# Esperar y descargar output
while True:
    h = requests.get(f'http://127.0.0.1:8188/history/{prompt_id}').json()
    if h.get(prompt_id):
        outputs = h[prompt_id]['outputs']
        for node_id, data in outputs.items():
            for img in data.get('images', []):
                url = f"http://127.0.0.1:8188/view?filename={img['filename']}&subfolder={img['subfolder']}&type={img['type']}"
                print(url)
        break
    time.sleep(1)
```
