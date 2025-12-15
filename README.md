# Run by docker
## install
```
docker pull ollama/ollama:0.13.3
```

## how to run
```
docker run -d -v ollama:/root/.ollama -p 11434:11434 --name ollama ollama/ollama:0.13.3
docker exec -it <container_id> bash
```

## run with model inside docker
* How to run
```
ollama run llama3
ollama run gemma3:27b
```

* What we will see
```
root@83c17a91a0b3:/# ollama run gemma3:12b
pulling manifest 
pulling manifest 
pulling e8ad13eff07a: 100% ▕███████████████████████████████████████▏ 8.1 GB                         
pulling e0a42594d802: 100% ▕███████████████████████████████████████▏  358 B                         
pulling dd084c7d92a3: 100% ▕███████████████████████████████████████▏ 8.4 KB                         
pulling 3116c5225075: 100% ▕███████████████████████████████████████▏   77 B                         
pulling 6819964c2bcf: 100% ▕███████████████████████████████████████▏  490 B                         
verifying sha256 digest 
writing manifest 
success
>>> hello
Hello there! 😊 

How can I help you today?
```

## how to test outside of docker
* test
```
curl http://localhost:11434/
```

* we will see on the console
```
Ollama is running
```

* test by sending prompt
```
curl http://localhost:11434/api/generate -d '{
  "model": "gemma3:12b",
  "prompt": "Write a short poem about the ocean.",
  "stream": false
}'
```



